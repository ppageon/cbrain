
#
# CBRAIN Project
#
# Copyright (C) 2008-2012
# The Royal Institution for the Advancement of Learning
# McGill University
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

#Restful controller for the CbrainTask resource.
class TasksController < ApplicationController

  Revision_info=CbrainFileRevision[__FILE__] #:nodoc:

  api_available

  before_filter :login_required

  def index #:nodoc:
    bourreaux = Bourreau.find_all_accessible_by_user(current_user).all
    bourreau_ids = bourreaux.map &:id

    scope = filter_variable_setup current_user.available_tasks.real_tasks.where( :bourreau_id => bourreau_ids )

    if request.format.to_sym == :xml
      @filter_params["sort_hash"]["order"] ||= "cbrain_tasks.updated_at"
      @filter_params["sort_hash"]["dir"]   ||= "DESC"
    else
      @filter_params["sort_hash"]["order"] ||= "cbrain_tasks.batch"
    end

    # Set sort order and make it persistent.
    @sort_order = @filter_params["sort_hash"]["order"]
    @sort_dir   = @filter_params["sort_hash"]["dir"]

    @showing_batch = false #i.e. don't show levels for individual entries.

    # In batch view...
    if @sort_order == "cbrain_tasks.batch"
      if @filter_params["filter_hash"]["batch_id"]  # we show a specific batch
        @sort_order      = "cbrain_tasks.rank, cbrain_tasks.level, cbrain_tasks.id"
        @sort_dir        = ""
        @showing_batch   = true
      else # batch view with several batches visible
        @sort_order = "cbrain_tasks.batch_id"
        @sort_dir   = 'DESC'
      end
    end

    scope = scope.includes( [:bourreau, :user, :group] ).readonly

    @total_tasks       = scope.count    # number of TASKS
    @total_space_known = scope.sum(:cluster_workdir_size)
    @total_space_unkn  = scope.where(:cluster_workdir_size => nil).where("cluster_workdir IS NOT NULL").count

    # For Pagination
    offset = (@current_page - 1) * @per_page

    if @filter_params["sort_hash"]["order"] == "cbrain_tasks.batch" && !@filter_params["filter_hash"]["batch_id"] && request.format.to_sym != :xml
      batch_ids                 = scope.order( "#{@sort_order} #{@sort_dir}" ).offset( offset ).limit( @per_page ).raw_first_column("distinct(cbrain_tasks.batch_id)")
      task_counts_in_batch      = scope.where(:batch_id => batch_ids).group(:batch_id).count
      full_batch_ids            = scope.raw_first_column("distinct(cbrain_tasks.batch_id)")
      full_task_counts_in_batch = scope.where(:batch_id => full_batch_ids).group(:batch_id).count
      @total_entries            = full_task_counts_in_batch.count

      @tasks = {} # hash batch_id => task_info
      batch_ids.each do |batch_id|
         num_tasks  = task_counts_in_batch[batch_id] || 0
         first_task = num_tasks == 1 ?
            scope.where(:batch_id => batch_id).first :
            scope.where(:batch_id => batch_id).order( [ :rank, :level, :id ] ).first
         next unless first_task.present? # in rare case a delete operation happens in background
         @tasks[batch_id] = { :first_task => first_task, :num_tasks => num_tasks }
      end
      pagination_list = batch_ids
    else
      @total_entries = @total_tasks
      task_list = scope.order( "#{@sort_order} #{@sort_dir}" ).offset( offset ).limit( @per_page ).all

      @tasks = {} # hash task_id -> task_info for a single task
      task_list.each do |t|
        @tasks[t.id] = { :first_task => t, :statuses => [t.status], :num_tasks => 1 }
      end
      pagination_list = task_list.map(&:id)
    end

    @paginated_list = WillPaginate::Collection.create(@current_page, @per_page) do |pager|
      pager.replace(pagination_list)
      pager.total_entries = @total_entries
      pager
    end

    current_session.save_preferences_for_user(current_user, :tasks, :per_page)

    @bourreau_status = {}
    bourreaux.each { |bo| @bourreau_status[bo.id] = bo.online? }
    respond_to do |format|
      format.html
      format.xml  { render :xml => @tasks }
      format.js
    end
  end

  def batch_list #:nodoc:
    scope = filter_variable_setup current_user.available_tasks.real_tasks.where(:batch_id => params[:batch_id] )

    scope = scope.includes( [:bourreau, :user, :group] ).order( "cbrain_tasks.rank, cbrain_tasks.level, cbrain_tasks.id" ).readonly(false)

    @tasks = scope
    @bourreau_status = {}
    Bourreau.find_all_accessible_by_user(current_user).all.each { |bo| @bourreau_status[bo.id] = bo.online?}

    render :layout => false
  end


  # GET /tasks/1
  # GET /tasks/1.xml
  def show #:nodoc:
    task_id     = params[:id]

    @task              = current_user.available_tasks.find(task_id)
    @task.add_new_params_defaults # auto-adjust params with new defaults if needed
    @run_number        = params[:run_number] || @task.run_number

    @stdout_lim        = params[:stdout_lim].to_i
    @stdout_lim        = 2000 if @stdout_lim <= 100 || @stdout_lim > 999999

    @stderr_lim        = params[:stderr_lim].to_i
    @stderr_lim        = 2000 if @stderr_lim <= 100 || @stderr_lim > 999999

    if ((request.format.to_sym != :xml) || params[:get_task_outputs]) && ! @task.workdir_archived?
      begin
        @task.capture_job_out_err(@run_number,@stdout_lim,@stderr_lim) # PortalTask method: sends command to bourreau to get info
      rescue Errno::ECONNREFUSED, EOFError, ActiveResource::ServerError, ActiveResource::TimeoutError, ActiveResource::MethodNotAllowed
        flash.now[:notice] = "Warning: the Execution Server '#{@task.bourreau.name}' for this task is not available right now."
        @task.cluster_stdout = "Execution Server is DOWN!"
        @task.cluster_stderr = "Execution Server is DOWN!"
        @task.script_text    = nil
      end
    end

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @task }
    end
  end

  def new #:nodoc:

    if params[:tool_id].blank?
      flash[:error] = "Please select a task to perform."
      redirect_to :controller  => :userfiles, :action  => :index
      return
    end

    @toolname         = Tool.find(params[:tool_id]).cbrain_task_class.demodulize

    @task             = CbrainTask.const_get(@toolname).new

    # Our new task object needs some initializing
    @task.params         = @task.class.wrapper_default_launch_args.clone
    @task.bourreau_id    = params[:bourreau_id]     # Just for compatibility with old code
    @task.tool_config_id = params[:tool_config_id]  # Normaly send by interface but it's optionnal
    @task.user           = current_user
    @task.group_id       = current_project.try(:id) || current_user.own_group.id
    @task.status         = "New"

    if @task.tool_config_id.present?
      @task.tool_config = ToolConfig.find(@task.tool_config_id)
      @task.bourreau_id = @task.tool_config.bourreau_id
    elsif @task.bourreau_id # Offer latest accessible tool config as default id ! @task.tool_config
      tool = @task.tool
      toolconfigs = ToolConfig.where( :bourreau_id => @task.bourreau_id, :tool_id => tool.id )
      toolconfigs.reject! { |tc| ! tc.can_be_accessed_by?(current_user) }
      lastest_toolconfig = toolconfigs.last
      @task.tool_config  = lastest_toolconfig if lastest_toolconfig
    end

    @tool_config = @task.tool_config # for acces in view

    # Filter list of files as provided by the get request
    file_ids = (params[:file_ids] || []) | current_session.persistent_userfile_ids_list
    @files            = Userfile.find_accessible_by_user(file_ids, current_user, :access_requested => :write) rescue []
    if @files.empty?
      flash[:error] = "You must select at least one file to which you have write access."
      redirect_to :controller  => :userfiles, :action  => :index
      return
    end

    @task.params[:interface_userfile_ids] = @files.map &:id

    # Other common instance variables, such as @data_providers and @bourreaux
    initialize_common_form_values

    # Custom initializing
    message = @task.wrapper_before_form
    unless message.blank?
      if message =~ /error/i
        flash.now[:error] = message
      else
        flash.now[:notice] = message
      end
    end

    # Generate the form.
    respond_to do |format|
      format.html # new.html.erb
    end

  # Catch any exception and re-raise them with a proper redirect.
  rescue => ex
    if ex.is_a?(CbrainException) && ex.redirect.nil?
      ex.redirect = { :controller => :userfiles, :action => :index }
    end
    raise ex
  end

  def edit #:nodoc:
    @task        = current_user.available_tasks.find(params[:id])
    @task.add_new_params_defaults # auto-adjust params with new defaults if needed
    @toolname    = @task.name
    @tool_config = @task.tool_config

    if @task.class.properties[:cannot_be_edited]
      flash[:error] = "This task is not meant to be edited.\n"
      redirect_to :action => :show, :id => params[:id]
      return
    end

    if @task.status !~ /Completed|Failed|Duplicated|Terminated/
      flash[:error] = "You cannot edit the parameters of an active task.\n"
      redirect_to :action => :show, :id => params[:id]
      return
    end

    # In order to edit older tasks that don't have :interface_userfile_ids
    # set, we initalize an empty one.
    params = @task.params
    params[:interface_userfile_ids] ||= []

    # Old API stored the data_provider_id in params, so move it
    @task.results_data_provider_id ||= params[:data_provider_id]
    params.delete(:data_provider_id) # keep it clean

    # Other common instance variables, such as @data_providers and @bourreaux
    initialize_common_form_values
    @bourreaux = [ @task.bourreau ] # override so we leave only one, even a non-active bourreau

    # Generate the form.
    respond_to do |format|
      format.html # edit.html.erb
    end

  end

def create #:nodoc:
    flash[:notice]     = ""
    flash[:error]      = ""
    flash.now[:notice] = ""
    flash.now[:error]  = ""

    # For historical reasons, the web interface sends both a tool_id and a tool_config_id.
    # Only the tool_config_id is really necessary, as itself the tool_config object supplies
    # the tool_id and the bourreau_id.
    # For support with the external APIs, we'll try to guess missing values if we
    # only receive a tool_config_id.
    params_tool_config_id = params[:cbrain_task][:tool_config_id] # can be nil
    tool_config           = ToolConfig.find(params_tool_config_id) rescue nil
    tool_config           = nil unless tool_config && tool_config.can_be_accessed_by?(current_user) &&
                             tool_config.bourreau_and_tool_can_be_accessed_by?(current_user)
    if tool_config
      params[:tool_id]                   = tool_config.tool_id     # replace whatever was there or not
      params[:cbrain_task][:bourreau_id] = tool_config.bourreau_id # replace whatever was there or not
    else
      params[:cbrain_task][:tool_config_id] = nil # ZAP value, it's incorrect; will likely cause a validation error later on.
    end

    @tool_config = tool_config # for acces in view

    # A brand new task object!
    @toolname         = Tool.find(params[:tool_id]).cbrain_task_class.demodulize
    @task             = CbrainTask.const_get(@toolname).new(params[:cbrain_task])
    @task.user_id   ||= current_user.id
    @task.group_id  ||= current_project.try(:id) || current_user.own_group.id
    @task.status      = "New" if @task.status.blank? || @task.status !~ /Standby/ # Standby is special.

    # Extract the Bourreau ID from the ToolConfig
    tool_config    = @task.tool_config
    if tool_config && tool_config.bourreau
      @task.bourreau = tool_config.bourreau
    else
      @task.errors.add(:base, "Please select a Server and a Version for the tool.")
    end

    # Security checks
    @task.user     = current_user           unless current_user.available_users.map(&:id).include?(@task.user_id)
    @task.group    = current_user.own_group unless current_user.available_groups.map(&:id).include?(@task.group_id)

    # Log revision number of portal.
    @task.addlog_current_resource_revision
    @task.addlog_context(self,"Created by #{current_user.login}")

    # Give a task the ability to do a refresh of its form
    commit_name = extract_params_key([ :refresh, :load_preset, :delete_preset, :save_preset ])
    commit_name = :refresh if params[:commit] =~ /refresh/i
    if commit_name == :refresh
      initialize_common_form_values
      flash.now[:notice] += @task.wrapper_refresh_form
      @task.valid? if @task.errors.empty?
      render :action => :new
      return
    end

    # Handle preset loads/saves
    unless @task.class.properties[:no_presets]
      if commit_name == :load_preset || commit_name == :delete_preset || commit_name == :save_preset
        handle_preset_actions
        initialize_common_form_values
        render :action => :new
        return
      end
    end

    # TODO validate @task here and if anything is wrong, render :new again

    # Custom initializing
    messages = ""
    begin
      messages += @task.wrapper_after_form
    rescue CbrainError, CbrainNotice => ex
      @task.errors.add(:base, "#{ex.class.to_s.sub(/Cbrain/,"")} in form: #{ex.message}\n")
    end

    unless @task.errors.empty? && @task.valid?
      flash.now[:error] += messages
      initialize_common_form_values
      respond_to do |format|
        format.html { render :action => 'new' }
        format.xml  { render :xml => @task.errors, :status => :unprocessable_entity }
      end
      return
    end

    # Detect automatic parallelism support; in that case
    # the tasks are created in the 'Standby' state, then
    # passed to the CbrainTask::Parallelizer class to
    # launch (one or many) parallelizer objects too.
    parallel_size = nil
    prop_parallel = @task.class.properties[:use_parallelizer] # true, or a number
    tc_ncpus      = @task.tool_config.ncpus || 1
    if prop_parallel && (tc_ncpus > 1)
      if prop_parallel.is_a?(Fixnum) && prop_parallel > 1
        parallel_size = tc_ncpus < prop_parallel ? tc_ncpus : prop_parallel # min of the two
      else
        parallel_size = tc_ncpus
      end
      parallel_size = nil if parallel_size < 1 # no need then
    end

    # Disable parallelizer if no Tool object yet created.
    if parallel_size && ! CbrainTask::Parallelizer.tool
      parallel_size = nil
      messages += "\nWarning: parallelization cannot be performed until the admin configures a Tool for it.\n"
    end

    # Prepare final list of tasks; from the one @task object we have,
    # we get a full array of clones of that task in tasklist
    @task.launch_time = Time.now # so grouping will work
    tasklist,task_list_message = @task.wrapper_final_task_list
    unless task_list_message.blank?
      messages += "\n" unless messages.blank? || messages =~ /\n$/
      messages += task_list_message
    end

    # Spawn a background process to launch the tasks.
    CBRAIN.spawn_with_active_records_if(request.format.to_sym != :xml, :admin, "Spawn Tasks") do

      spawn_messages = ""

      share_wd_Nid_to_tid = {} # a negative number -> task_id

      batch_id = nil # all tasks will get the same batch_id ONCE the first task is saved.
      tasklist.each do |task|
        begin
          if parallel_size && task.class == @task.class # Parallelize only tasks of same class as original
            if (task.status || 'New') !~ /New|Standby/ # making sure task programmer knows what he's doing
              raise ScriptError.new("Trying to parallelize a task, but the status was '#{task.status}' instead of 'New' or 'Standby'.")
            end
            task.status = "Standby" # force it there; the parallelizer with turn it back to 'New' later on
          else
            task.status = "New" if task.status.blank?
          end
          share_wd_Nid = task.share_wd_tid # the negative number for the set of tasks sharing a workdir
          task.batch_id ||= batch_id # will be nil for the first task, but we'll reset it a bit later to a real ID
          if share_wd_Nid.present? && share_wd_Nid <= 0
            task.share_wd_tid = share_wd_Nid_to_tid[share_wd_Nid] # will be nil for first task in set, which is right
            task.save! # this sets batch_id if it's still nil, in an after_save callback
            share_wd_Nid_to_tid[share_wd_Nid] = task.id
          else
            task.save! # this sets batch_id if it's still nil, in an after_save callback
          end
          # First task in the batch is the one to determine the batch_id for the other tasks
          batch_id ||= task.batch_id
        rescue => ex
          spawn_messages += "This task #{task.name} seems invalid: #{ex.class}: #{ex.message}.\n"
        end
      end

      spawn_messages += @task.wrapper_after_final_task_list_saved(tasklist)  # TODO check, use messages?

      # Create parallelizers, if needed
      if parallel_size
        paral_tasklist = tasklist.select { |t| t.class == @task.class }
        paral_info = CbrainTask::Parallelizer.create_from_task_list(paral_tasklist, :group_size => parallel_size)
        paral_messages = paral_info[0] # [1] is an array of Parallelizers, [2] an array of single tasks.
        if ! paral_messages.blank?
          spawn_messages += "\n" unless spawn_messages.blank? || spawn_messages =~ /\n$/
          spawn_messages += paral_messages
        end
      end

      # Send a start worker command to each affected bourreau
      bourreau_ids = tasklist.map &:bourreau_id
      bourreau_ids.uniq.each do |bourreau_id|
        Bourreau.find(bourreau_id).send_command_start_workers rescue true
      end

      unless spawn_messages.blank?
        Message.send_message(current_user, {
          :header        => "Submitted #{tasklist.size} #{@task.pretty_name} tasks; some messages follow.",
          :message_type  => :notice,
          :variable_text => spawn_messages
          }
        )
      end

    end

    if tasklist.size == 1
      flash[:notice] += "Launching a #{@task.pretty_name} task in background."
    else
      flash[:notice] += "Launching #{tasklist.size} #{@task.pretty_name} tasks in background."
    end
    flash[:notice] += "\n"            unless messages.blank? || messages =~ /\n$/
    flash[:notice] += messages + "\n" unless messages.blank?

    respond_to do |format|
      format.html { redirect_to :controller => :tasks, :action => :index }
      format.xml  { render :xml => tasklist }
    end
  end

  def update #:nodoc:

    flash[:notice]     = ""
    flash[:error]      = ""
    flash.now[:notice] = ""
    flash.now[:error]  = ""

    id = params[:id]
    @task = current_user.available_tasks.find(id)
    @task.add_new_params_defaults # auto-adjust params with new defaults if needed

    # Save old params and update the current task to reflect
    # the form's content.
    old_params   = @task.params.clone
    new_att      = params[:cbrain_task] || {} # not the TASK's params[], the REQUEST's params[]
    new_att      = new_att.reject { |k,v| k =~ /^(cluster_jobid|cluster_workdir|status|batch_id|launch_time|prerequisites|share_wd_tid|run_number|level|rank|cluster_workdir_size|workdir_archived|workdir_archive_userfile_id)$/ } # some attributes cannot be changed through the controller
    old_tool_config = @task.tool_config
    old_bourreau    = @task.bourreau
    @task.attributes = new_att # just updates without saving
    @task.restore_untouchable_attributes(old_params)

    # Bourreau ID must stay the same; tool config must be one associated with it
    @task.bourreau = old_bourreau
    unless @task.tool_config && @task.tool_config.bourreau_id == old_bourreau.id
      @task.tool_config = old_tool_config
    end

    # Security checks
    @task.user     = @task.changed_attributes['user_id']  || @task.user_id   unless current_user.available_users.map(&:id).include?(@task.user_id)
    @task.group    = @task.changed_attributes['group_id'] || @task.group_id  unless current_user.available_groups.map(&:id).include?(@task.group_id)

    # Give a task the ability to do a refresh of its form
    commit_name = extract_params_key([ :refresh, :load_preset, :delete_preset, :save_preset ], :whatever)
    commit_name = :refresh if params[:commit] =~ /refresh/i
    if commit_name == :refresh
      initialize_common_form_values
      flash[:notice] += @task.wrapper_refresh_form
      @task.valid? if @task.errors.empty?
      render :action => :edit
      return
    end

    # Handle preset loads/saves
    unless @task.class.properties[:no_presets]
      if commit_name == :load_preset || commit_name == :delete_preset || commit_name == :save_preset
        handle_preset_actions
        initialize_common_form_values
        @bourreaux = [ @task.bourreau ] # override so we leave only one, even a non-active bourreau
        @task.valid?
        render :action => :edit
        return
      end
    end

    # Final update to the task object, this time we save it.
    messages = ""
    begin
      messages += @task.wrapper_after_form
    rescue CbrainError, CbrainNotice => ex
      @task.errors.add(:base, "#{ex.class.to_s.sub(/Cbrain/,"")} in form: #{ex.message}\n")
    end

    unless @task.errors.empty? && @task.valid?
      initialize_common_form_values
      flash.now[:error] += messages
      render :action => 'edit'
      return
    end

    # Log revision number of portal.
    @task.addlog_current_resource_revision

    # Log task params changes
    @task.log_params_changes(old_params,@task.params)

    # Log and save normal attributes of the task
    @task.save_with_logging(current_user, %w( results_data_provider_id ))

    flash[:notice] += messages + "\n" unless messages.blank?
    flash[:notice] += "New task parameters saved. See the logs for changes, if any.\n"
    redirect_to :action => :show, :id => @task.id
  end

  def update_multiple #:nodoc:

    # Construct task_ids and batch_ids
    task_ids    = Array(params[:tasklist]  || [])
    batch_ids   = Array(params[:batch_ids] || [])

    if batch_ids.delete "nil"
      task_ids += filter_variable_setup(CbrainTask.real_tasks.where( :batch_id => nil )).select("id").raw_first_column
    end
    task_ids   += filter_variable_setup(CbrainTask.real_tasks.where( :batch_id => batch_ids )).select("id").raw_first_column
    task_ids    = task_ids.map(&:to_i).uniq

    commit_name = extract_params_key([ :update_user_id, :update_group_id, :update_results_data_provider_id, :update_tool_config_id ])

    # If commit_name undef
    unless commit_name.present?
      flash[:error] = "No operation to perform."
      redirect_to :action => :index, :format  => request.format.to_sym
      return
    end

    unable_to_update = ""
    field_to_update  =
      case commit_name
        when :update_user_id
          new_user_id = params[:task][:user_id].to_i
          unable_to_update = "user"   if
          ! current_user.available_users.where(:id => new_user_id).exists?
          :user
        when :update_group_id
          new_group_id = params[:task][:group_id].to_i
          unable_to_update = "project" if
          ! current_user.available_groups.where(:id => new_group_id).exists?
          :group
        when :update_results_data_provider_id
          new_dp_id = params[:task][:results_data_provider_id].to_i
          unable_to_update = "data provider" if
          ! DataProvider.find_all_accessible_by_user(current_user).where(:id => new_dp_id).exists?
          :results_data_provider
        when :update_tool_config_id
          new_tool_config = ToolConfig.find(params[:task][:tool_config_id].to_i)
          unable_to_update = "tool version" if
            ! new_tool_config.bourreau_and_tool_can_be_accessed_by?(current_user)
          :tool_config
        else
        :unknown
      end

    if unable_to_update.present?
      flash[:error] = "You do not have access to this #{unable_to_update}."
      redirect_to :action => :index, :format  => request.format.to_sym
      return
    end

    # For unknown field
    if field_to_update == :unknown
      flash[:error] = "Unknown field to update."
      redirect_to :action => :index, :format  => request.format.to_sym
      return
    end

    do_in_spawn   = task_ids.size > 5
    success_count = 0
    success_list  = []
    failed_list   = {}

    CBRAIN.spawn_with_active_records_if(do_in_spawn,current_user,"Sending update to tasks") do
      accessible_bourreau = Bourreau.find_all_accessible_by_user(current_user)
      tasklist            = CbrainTask.where(:id => task_ids, :bourreau_id => accessible_bourreau).all

      # Remove tasks who aren't accessible by current_user
      new_tasklist = tasklist.dup
      new_tasklist.reject! { |task| ! task.has_owner_access?(current_user) }
      failed_tasks = tasklist - new_tasklist
      failed_list["you don't have access to this task(s)"]  = failed_tasks if failed_tasks.present?
      tasklist     = new_tasklist

      operation =
        case field_to_update
          when :user
            ["update_attributes", {:user_id => new_user_id}]
          when :group
            user_to_avail_group_ids = {}
            new_tasklist = tasklist.dup
            new_tasklist.reject! do |task|
              t_uid = task.user_id
              # Task user need to have access to new group
              user_to_avail_group_ids[t_uid] ||= User.find(t_uid).available_groups.map(&:id).index_by { |id| id }
              (! user_to_avail_group_ids[t_uid][new_group_id])
            end
            failed_tasks = tasklist - new_tasklist
            failed_list["new group is not accessible by task's owner"] = failed_tasks if failed_tasks.present?
            tasklist     = new_tasklist
            ["update_attributes", {:group_id => new_group_id}]
          when :results_data_provider
            user_to_avail_dp_ids = {}
            new_tasklist = tasklist.dup
            new_tasklist.reject! do |task|
              t_uid = task.user_id
              # Task user need to have access to new data provider
              user_to_avail_dp_ids[t_uid] ||= DataProvider.find_all_accessible_by_user(User.find(t_uid)).index_by { |dp| dp.id }
              (! user_to_avail_dp_ids[t_uid][new_dp_id])
            end
            failed_tasks = tasklist - new_tasklist
            failed_list["new data provider is not accessible by task's owner"] = failed_tasks if failed_tasks.present?
            tasklist     = new_tasklist
            ["update_attributes", {:results_data_provider_id => new_dp_id}]
          when :tool_config
            user_to_avail_new_tool_config = {}
            old_tcid_to_tool_id           = {}
            new_tasklist = tasklist.dup
            new_tasklist.reject! do |task|
              t_uid    = task.user_id
              old_tcid = task.tool_config_id
              old_bid  = task.bourreau_id
              # Task user need to have access to bourreau and tool linked to tool_config
              user_to_avail_new_tool_config[t_uid] ||= new_tool_config.bourreau_and_tool_can_be_accessed_by?(User.find(t_uid)) ? 1 : 0
              # old tool_config and new tool_config need to concern same tool
              old_tcid_to_tool_id[old_tcid] ||= ToolConfig.find(old_tcid).tool_id
              # (user has access to new tc)                     (new tc is same tool as old tc)                         (new tc has same bourreau as old tc)
              (user_to_avail_new_tool_config[t_uid] == 0) || (old_tcid_to_tool_id[old_tcid] != tool_config.tool_id) || (old_bid != new_tool_config.bourreau_id)
            end
            failed_tasks = tasklist - new_tasklist
            failed_list["error when updating tool config"] = failed_tasks if failed_tasks.present?
            tasklist     = new_tasklist
            ["update_attributes", {:tool_config_id => new_tool_config.id}]
        end

      tasklist.each { |task| success_list << task if task.send(*operation) }

      if do_in_spawn
        # Message for successful actions
        if success_list.present?
          notice_message_sender("Finished sending update to your task(s)", success_list)
        end
        # Message for failed actions
        if failed_list.present?
          error_message_sender("Failed to update your task(s)", failed_list)
        end
      end

    end # End of spawn_if block

    if do_in_spawn
      flash[:notice] = "The tasks are being updated in background."
    else
     flash[:notice] = "Successfully update #{view_pluralize(success_list.count, "task")}."   if success_list.present?
     failure_count  = 0
     failed_list.each_value { |v| failure_count += v.size }
     flash[:error]  = "Failed to update #{view_pluralize(failure_count, "task")}." if failure_count > 0
    end

    redirect_to :action => :index, :format  => request.format.to_sym
  end

  #This action handles requests to modify the status of a given task.
  #Potential operations are:
  #[*Hold*] Put the task on hold (while it is queued).
  #[*Release*] Release task from <tt>On Hold</tt> status (i.e. put it back in the queue).
  #[*Suspend*] Stop processing of the task (while it is on cpu).
  #[*Resume*] Release task from <tt>Suspended</tt> status (i.e. continue processing).
  #[*Terminate*] Kill the task, while maintaining its temporary files and its entry in the database.
  #[*Delete*] Kill the task, delete the temporary files and remove its entry in the database.
  def operation #:nodoc:
    operation   = params[:operation]
    tasklist    = params[:tasklist]  || []
    tasklist    = [ tasklist ] unless tasklist.is_a?(Array)
    batch_ids   = params[:batch_ids] || []
    batch_ids   = [ batch_ids ] unless batch_ids.is_a?(Array)
    if batch_ids.delete "nil"
      tasklist += filter_variable_setup(CbrainTask.where( :batch_id => nil )).select("id").raw_first_column
    end
    tasklist += filter_variable_setup(CbrainTask.where( :batch_id => batch_ids )).select("id").raw_first_column

    tasklist = tasklist.map(&:to_i).uniq

    flash[:error]  ||= ""
    flash[:notice] ||= ""

    if operation.nil? || operation.empty?
       flash[:notice] += "Task list has been refreshed.\n"
       redirect_to :action => :index
       return
     end

    if tasklist.empty?
      flash[:error] += "No task selected? Selection cleared.\n"
      redirect_to :action => :index
      return
    end

    # Prepare counters for how many tasks affected.
    sent_ok      = 0
    sent_failed  = 0
    sent_skipped = 0

    skipped_list = {}
    success_list = []
    failed_list  = {}

    # Decide in which conditions we spawn a background job to send
    # the operation to the tasks...
    do_in_spawn  = tasklist.size > 5

    # This block will either run in background or not depending
    # on do_in_spawn
    CBRAIN.spawn_with_active_records_if(do_in_spawn,current_user,"Sending #{operation} to tasks") do

      tasks = []
      tasklist.each do |task_id|

        begin
          task = current_user.available_tasks.find(task_id)
        rescue
          (failed_list["Task not available"] ||= [])
          next
        end

        if task.user_id != current_user.id && current_user.type != 'AdminUser'
          (skipped_list["you not allowed to #{operation} this task(s)"] ||= []) << task
          next
        end

        tasks << task
      end

      # Some security validations
      new_bourreau_id = params[:dup_bourreau_id].presence
      archive_dp_id   = params[:archive_dp_id].presence
      new_bourreau_id = nil unless new_bourreau_id && Bourreau.find_all_accessible_by_user(current_user).where(:id => new_bourreau_id).exists?
      archive_dp_id   = nil unless archive_dp_id   && DataProvider.find_all_accessible_by_user(current_user).where(:id => archive_dp_id).exists?

      # Go through tasks, grouped by bourreau
      grouped_tasks = tasks.group_by &:bourreau_id
      grouped_tasks.each do |pair_bid_tasklist|
        bid       = pair_bid_tasklist[0]
        btasklist = pair_bid_tasklist[1]
        bourreau  = Bourreau.find(bid)
        begin
          if operation == 'delete'
            bourreau.send_command_alter_tasks(btasklist,'Destroy') # TODO parse returned command object?
            success_list << btasklist
            next
          end
          new_status  = PortalTask::OperationToNewStatus[operation] # from HTML form keyword to Task object keyword
          oktasks = btasklist.select do |t|
            cur_status  = t.status
            allowed_new = PortalTask::AllowedOperations[cur_status] || []
            new_status && allowed_new.include?(new_status)
          end
          if oktasks.size > 0
            bourreau.send_command_alter_tasks(oktasks, new_status, new_bourreau_id, archive_dp_id) # TODO parse returned command object?
            succes_list << oktasks
          end
          skippedtasks = btasklist - oktasks
          skipped_list["you are not allowed to #{operation} for"] = skippedtasks if skippedtasks.present?
        rescue => e
          (failed_list[e.message] ||= []) << btasklist
        end
      end # foreach bourreaux' tasklist

      if do_in_spawn
        if success_list.present?
          notice_message_sender("Finished sending '#{operation}' to your tasks.",success_list)
        end
        if skipped_list.present?
          error_message_sender("Task skipped when sending '#{operation}' to your tasks.",skipped_list)
        end
        if failed_list.present?
          error_message_sender("Error when sending '#{operation}' to your tasks.",failed_list)
        end
      end

    end # End of spawn_if block

    if do_in_spawn
      flash[:notice] += "The tasks are being notified in background."
    else
      failure_count  = 0
      failed_list.each_value { |v| failure_count += v.size }
      skipped_count  = 0
      skipped_list.each_value { |v| skipped_count += v.size }
      flash[:notice] += "Number of tasks notified: #{success_list.count} OK, #{skipped_count} skipped, #{failure_count} failed.\n"
    end

    #current_user.addlog_context(self,"Sent '#{operation}' to #{tasklist.size} tasks.")
    redirect_to :action => :index, :format  => request.format.to_sym

  end # method 'operation'



  #####################################################################
  # Private Methods For Form Support
  #####################################################################

  private

  # Some useful variables for the views for 'new' and 'edit'
  def initialize_common_form_values #:nodoc:

    # Find the list of Bourreaux that are both available and support the tool
    tool         = @task.tool
    bourreau_ids = tool.bourreaux.map &:id
    bourreaux    = Bourreau.find_all_accessible_by_user(current_user).where( :online => true, :id => bourreau_ids ).all

    # Presets
    unless @task.class.properties[:no_presets]
      site_preset_tasks = []
      unless current_user.site.blank?
        manager_ids = current_user.site.managers.map &:id
        site_preset_tasks = CbrainTask.where( :status => 'SitePreset', :user_id => manager_ids )
      end
      own_preset_tasks = current_user.cbrain_tasks.where( :type => @task.class.to_s, :status => 'Preset' )
      @own_presets  = own_preset_tasks.collect  { |t| [ t.short_description, t.id ] }
      @site_presets = site_preset_tasks.collect { |t| [ "#{t.short_description} (by #{t.user.login})", t.id ] }
      @all_presets = []
      @all_presets << [ "Site Presets",     @site_presets ] if @site_presets.size > 0
      @all_presets << [ "Personal Presets", @own_presets  ] if @own_presets.size > 0
      @offer_site_preset = current_user.has_role? :site_manager
      #@own_presets = [ [ "Personal1", "1" ], [ "Personal2", "2" ] ]
      #@all_presets = [ [ "Site Presets", [ [ "Dummy1", "1" ], [ "Dummy2", "2" ] ] ], [ "Personal Presets", @own_presets ] ]
    end

    # Tool Configurations
    valid_bourreau_ids = bourreaux.index_by &:id
    valid_bourreau_ids = { @task.bourreau_id => @task.bourreau } if ! @task.new_record? # existing tasks have more limited choices.
    @tool_configs      = tool.tool_configs # all of them, too much actually
    @tool_configs.reject! do |tc|
      tc.bourreau_id.blank? ||
      ! valid_bourreau_ids[tc.bourreau_id] ||
      ! tc.can_be_accessed_by?(@task.user)
    end

  end

  # This method handle the logic of loading and saving presets.
  def handle_preset_actions #:nodoc:
    commit_name  = extract_params_key([ :load_preset, :delete_preset, :save_preset ], :whatewer)

    if commit_name == :load_preset
      preset_id = params[:load_preset_id] # used for delete too
      if (! preset_id.blank?) && preset = CbrainTask.where(:id => preset_id, :status => [ 'Preset', 'SitePreset' ]).first
        old_params = @task.params.clone
        @task.params         = preset.params
        @task.restore_untouchable_attributes(old_params, :include_unpresetable => true)
        if preset.group && preset.group.can_be_accessed_by?(current_user)
          @task.group = preset.group
        end
        if preset.tool_config && preset.tool_config.can_be_accessed_by?(current_user) && (@task.new_record? || preset.tool_config.bourreau_id == @task.bourreau_id)
          @task.tool_config = preset.tool_config
        end
        @task.bourreau = @task.tool_config.bourreau if @task.tool_config
        flash[:notice] += "Loaded preset '#{preset.short_description}'.\n"
      else
        flash[:notice] += "No preset selected, so parameters are unchanged.\n"
      end
    end

    if commit_name == :delete_preset
      preset_id = params[:load_preset_id] # used for delete too
      if (! preset_id.blank?) && preset = CbrainTask.where(:id => preset_id, :status => [ 'Preset', 'SitePreset' ]).first
        if preset.user_id == current_user.id
          preset.delete
          flash[:notice] += "Deleted preset '#{preset.short_description}'.\n"
        else
          flash[:notice] += "Cannot delete a preset that doesn't belong to you.\n"
        end
      else
        flash[:notice] += "No preset selected, so parameters are unchanged.\n"
      end
    end

    if commit_name == :save_preset
      preset_name = params[:save_preset_name]
      preset = nil
      if ! preset_name.blank?
        preset = @task.dup # not .clone, as of Rails 3.1.10
        preset.description = preset_name
      else
        preset_id = params[:save_preset_id]
        preset    = CbrainTask.where(:id => preset_id, :status => [ 'Preset', 'SitePreset' ]).first
        cb_error "No such preset ID '#{preset_id}'" unless preset
        if preset.user_id != current_user.id
          flash[:error] += "Cannot update a preset that does not belong to you.\n"
          return
        end
        preset.params = @task.params.clone
      end

      # Cleanup stuff that don't need to go into a preset
      preset.status               = params[:save_as_site_preset].blank? ? 'Preset' : 'SitePreset'
      preset.bourreau             = nil # convention: presets have bourreau id set to 0
      preset.bourreau_id          = 0 # convention: presets have bourreau id set to 0
      preset.batch_id             = nil
      preset.cluster_jobid        = nil
      preset.cluster_workdir      = nil
      preset.cluster_workdir_size = nil
      preset.launch_time          = nil
      preset.prerequisites        = {}
      preset.rank                 = 0
      preset.level                = 0
      preset.run_number           = nil
      preset.share_wd_tid         = nil
      preset.workdir_archived     = false
      preset.workdir_archive_userfile_id = nil
      preset.wrapper_untouchable_params_attributes.each_key do |untouch|
        preset.params.delete(untouch) # no need to save these eh?
      end
      preset.save!

      flash[:notice] += "Saved preset '#{preset.short_description}'.\n"
    end
  end

  def resource_class #:nodoc:
    CbrainTask
  end

  def filter_variable_setup(starting_scope)
    @header_scope = starting_scope
    @header_scope = @header_scope.where( :group_id => current_project.id ) if current_project

    @filtered_scope = base_filtered_scope(@header_scope)

    if @filter_params["filter_hash"]["bourreau_id"].blank?
      @filtered_scope = @filtered_scope.where( :bourreau_id => Bourreau.find_all_accessible_by_user(current_user).all.map(&:id) )
    end

    # Handle custom filters
    @filter_params["filter_custom_filters_array"] ||= []
    @filter_params["filter_custom_filters_array"] &= current_user.custom_filter_ids.map(&:to_s)
    @filter_params["filter_custom_filters_array"].each do |custom_filter_id|
      custom_filter = TaskCustomFilter.find(custom_filter_id)
      @filtered_scope = custom_filter.filter_scope(@filtered_scope)
    end

    @filtered_scope
  end

  # Warning: private context in effect here.

end
