
#
# Rake tasks for CBRAIN plugins management
#

namespace :cbrain do
  namespace :plugins do



    #====================
    namespace :install do
    #====================



    ##########################################################################
    desc "Install and configure CBRAIN plugins"
    ##########################################################################
    task :all => [ :plugins, :public_assets ]



    ##########################################################################
    desc "Create the symbolic links to tasks and files found in CBRAIN plugin packages"
    ##########################################################################
    task :plugins do

      puts "Installing tasks and userfiles, as found in installed CBRAIN plugin packages..."

      # Unfortunately we don't have access to cbrain.rb where some useful constants are defined in the
      # CBRAIN class, such as CBRAIN::TasksPlugins_Dir ; if we ever change where plugins are stored, we
      # have to update this here and the cbrain.rb file too.
      plugins_dir           = Rails.root            + "cbrain_plugins"
      installed_plugins_dir = plugins_dir           + "installed-plugins"
      tasks_plugins_dir     = installed_plugins_dir + "cbrain_task"
      userfiles_plugins_dir = installed_plugins_dir + "userfiles"

      Dir.chdir(plugins_dir.to_s) do
        packages = Dir.glob('*').reject { |path| path =~ /^(installed-plugins)$/ }.select { |f| File.directory?(f) }

        puts "Skipping: No CBRAIN packages detected in plugins directory '#{plugins_dir}'." if packages.empty?

        # Each package
        packages.each do |package|
          puts "Checking plugins in package '#{package}'..."
          Dir.chdir(package) do

            # Setup each userfile plugin

            files = Dir.glob('userfiles/*').select { |f| File.directory?(f) }
            puts "Found #{files.size} file(s) to set up..."
            files.each do |u_slash_f|                                  # "userfiles/abcd"
              myfile           = Pathname.new(u_slash_f).basename.to_s # "abcd"
              symlink_location = userfiles_plugins_dir + myfile
              plugin_location  = plugins_dir           + package + u_slash_f
              symlink_value    = plugin_location.relative_path_from(symlink_location.parent)
              #puts "#{u_slash_f} #{myfile}\n TS=#{symlink_location}\n PL=#{plugin_location}\n LL=#{symlink_value}"

              if File.exists?(symlink_location)
                if File.symlink?(symlink_location)
                  if File.readlink(symlink_location) == symlink_value.to_s
                    puts "-> Userfile already setup: '#{myfile}'."
                    next
                  end
                  puts "-> Error: there is already a symlink with an unexpected value here:\n   #{symlink_location}"
                  next
                end
                puts "-> Error: there is already an entry (file or directory) here:\n   #{symlink_location}"
                next
              end

              puts "-> Creating symlink for userfile '#{myfile}'."
              File.symlink symlink_value, symlink_location
              #puts "  #{symlink_value} as #{symlink_location}"
            end


            # Setup each cbrain_task plugin

            tasks = Dir.glob('cbrain_task/*').select { |f| File.directory?(f) }
            puts "Found #{tasks.size} tasks(s) to set up..."
            tasks.each do |u_slash_t|                                  # "cbrain_task/abcd"
              mytask           = Pathname.new(u_slash_t).basename.to_s # "abcd"
              symlink_location = tasks_plugins_dir + mytask
              plugin_location  = plugins_dir       + package + u_slash_t
              symlink_value    = plugin_location.relative_path_from(symlink_location.parent)

              if File.exists?(symlink_location)
                if File.symlink?(symlink_location)
                  if File.readlink(symlink_location) == symlink_value.to_s
                    puts "-> Task already setup: '#{mytask}'."
                    next
                  end
                  puts "-> Error: there is already a symlink with an unexpected value here:\n   #{symlink_location}"
                  next
                end
                puts "-> Error: there is already an entry (file or directory) here:\n   #{symlink_location}"
                next
              end

              puts "-> Creating symlink for task '#{mytask}'."
              File.symlink symlink_value, symlink_location
              File.symlink "cbrain_task_class_loader.rb", "#{symlink_location}.rb" # intelligent loader wrapper
              #puts "  #{symlink_value} as #{symlink_location}"
            end

          end # chdir package
        end # each package
      end # chdir plugins

    end # task :plugins



    ##########################################################################
    desc "Create the symbolic links for public assets of installed CBRAIN tasks and userfiles."
    ##########################################################################
    task :public_assets do

      puts "Adjusting paths to public assets for tasks and userfiles..."

      # Paths to public assets exposed by the web server
      public_root      = Rails.root  + "public"
      public_tasks     = public_root + "cbrain_plugins/cbrain_tasks" # normally empty and part of CBRAIN dist
      public_userfiles = public_root + "cbrain_plugins/userfiles" # normally empty and part of CBRAIN dist

      # Unfortunately we don't have access to cbrain.rb where some useful constants are defined in the
      # CBRAIN class, such as CBRAIN::TasksPlugins_Dir ; if we ever change where plugins are stored, we
      # have to update this here and the cbrain.rb file too.
      plugins_dir           = Rails.root            + "cbrain_plugins"
      installed_plugins_dir = plugins_dir           + "installed-plugins"
      tasks_plugins_dir     = installed_plugins_dir + "cbrain_task"
      userfiles_plugins_dir = installed_plugins_dir + "userfiles"

      Dir.chdir(public_userfiles) do
        userfiles_public_dirs = Dir.glob(userfiles_plugins_dir + "*/views/public")
        if userfiles_public_dirs.empty?
          puts "No public assets made available by any userfiles."
        else
          puts "Found #{userfiles_public_dirs.size} userfile(s) with public assets to set up..."
        end

        userfiles_public_dirs.each do |fullpath| # "/a/b/rails/cbrain_plugins/installed-plugins/userfiles/text_file/views/public"
          relpath  = Pathname.new(fullpath).relative_path_from(public_tasks) # ../(...)/cbrain_plugins/installed-plugins/userfiles/text_file/views/public
          filename = relpath.parent.parent.basename # "text_file"
          if File.exists?(filename)
            puts "-> Assets for userfile already set up: '#{filename}'."
            next
          end
          puts "-> Creating assets symbolic link for userfile '#{filename}'."
          File.symlink(relpath,filename)  # "text_file" -> "../(...)/cbrain_plugins/installed-plugins/userfiles/text_file/views/public"
        end
      end

      Dir.chdir(public_tasks) do
        tasks_public_dirs = Dir.glob(tasks_plugins_dir + "*/views/public")
        if tasks_public_dirs.empty?
          puts "-> No public assets made available by any tasks."
        else
          puts "Found #{tasks_public_dirs.size} task(s) with public assets to set up..."
        end

        tasks_public_dirs.each do |fullpath| # "/a/b/rails/cbrain_plugins/installed-plugins/cbrain_tasks/diagnostics/views/public"
          relpath  = Pathname.new(fullpath).relative_path_from(public_tasks) # ../(...)/cbrain_plugins/cbrain_tasks/diagnostics/views/public
          taskname = relpath.parent.parent.basename # "diagnostics"
          if File.exists?(taskname)
            puts "-> Assets for task already set up: '#{taskname}'."
            next
          end
          puts "-> Creating assets symbolic link for task '#{taskname}'."
          File.symlink(relpath,taskname)  # "diagnostics" -> "../(...)/cbrain_plugins/installed-plugins/cbrain_tasks/diagnostics/views/public"
        end
      end

    end # task :public_assets

    end # namespace install




    #====================
    namespace :clean do
    #====================



    ##########################################################################
    desc "Clean all CBRAIN plugins installation symlinks "
    ##########################################################################
    task :all => [ :plugins, :public_assets ] do
      puts "All done. You might want to run the rake task 'cbrain:plugins:install:all' now to reinstall everything properly."
    end



    ##########################################################################
    desc "Clean up symbolic links for tasks and userfiles of CBRAIN plugin packages"
    ##########################################################################
    task :plugins do

      # Unfortunately we don't have access to cbrain.rb where some useful constants are defined in the
      # CBRAIN class, such as CBRAIN::TasksPlugins_Dir ; if we ever change where plugins are stored, we
      # have to update this here and the cbrain.rb file too.
      plugins_dir           = Rails.root            + "cbrain_plugins"
      installed_plugins_dir = plugins_dir           + "installed-plugins"
      tasks_plugins_dir     = installed_plugins_dir + "cbrain_task"
      userfiles_plugins_dir = installed_plugins_dir + "userfiles"

      puts "Erasing all symlinks for userfiles installed from CBRAIN plugins..."
      Dir.chdir(userfiles_plugins_dir.to_s) do
        Dir.glob('*').select { |f| File.symlink?(f) }.each do |f|
          puts "-> Erasing link for userfile '#{f}'."
          File.unlink(f)
        end
      end

      puts "Erasing all symlinks for tasks installed from CBRAIN plugins..."
      Dir.chdir(tasks_plugins_dir.to_s) do
        Dir.glob('*').select { |f| File.symlink?(f) }.each do |f|
          puts "-> Erasing link for task '#{f}'."
          File.unlink(f)
        end
      end

    end



    ##########################################################################
    desc "Clean up symbolic links for public assets of installed CBRAIN tasks and userfiles."
    ##########################################################################
    task :public_assets do

      # Paths to public assets exposed by the web server
      public_root      = Rails.root  + "public"
      public_tasks     = public_root + "cbrain_plugins/cbrain_tasks" # normally empty and part of CBRAIN dist
      public_userfiles = public_root + "cbrain_plugins/userfiles" # normally empty and part of CBRAIN dist

      puts "Erasing all symlinks for public assets of userfiles installed from CBRAIN plugins..."
      Dir.chdir(public_userfiles.to_s) do
        Dir.glob('*').select { |f| File.symlink?(f) }.each do |f|
          puts "-> Erasing link for assets of userfile '#{f}'."
          File.unlink(f)
        end
      end

      puts "Erasing all symlinks for public assets of tasks installed from CBRAIN plugins..."
      Dir.chdir(public_tasks.to_s) do
        Dir.glob('*').select { |f| File.symlink?(f) }.each do |f|
          puts "-> Erasing link for assets of task '#{f}'."
          File.unlink(f)
        end
      end

    end



    ##########################################################################
    desc "Remove leftover (orphan) tasks and userfiles from removed CBRAIN plugins"
    ##########################################################################
    task :orphans => :environment do

      # We'll need all available userfile and task models
      Rails.application.eager_load!

      # Available userfile and task types
      userfile_classes = Userfile.descendants.map(&:name)
      task_classes     = CbrainTask.descendants.map(&:name)

      raise "Error: cannot find any userfile subclasses?!?" if userfile_classes.blank?
      raise "Error: cannot find any task subclasses?!?"     if task_classes.blank?

      # NOTE: direct SQL is used here to avoid ActiveRecord throwing a SubclassNotFound exception on
      # objects that would only wound up deleted.
      puts "Removing orphan userfiles..."
      deleted_userfiles = Userfile.connection.delete("
        DELETE FROM userfiles
        WHERE type NOT IN ('#{userfile_classes.join("','")}')
      ") || 0

      puts "Removing orphan tasks..."
      deleted_tasks     = CbrainTask.connection.delete("
        DELETE FROM cbrain_tasks
        WHERE type NOT IN ('#{task_classes.join("','")}')
      ") || 0

      if deleted_userfiles == 0 && deleted_tasks == 0
        puts "No orphans (userfile or task) found."
      else
        deleted = deleted_userfiles + deleted_tasks
        puts "#{deleted} orphan(s) (#{deleted_userfiles} userfile(s) and #{deleted_tasks} task(s)) removed."
      end

    end

    end # namespace clean




    #====================
    namespace :check do
    #====================



    ##########################################################################
    desc "Check for leftover (orphan) tasks or userfiles from removed CBRAIN plugins"
    ##########################################################################
    task :orphans => :environment do

      # We'll need all available userfile and task models
      Rails.application.eager_load!

      # Available userfile and task types
      userfile_classes = Userfile.descendants.map(&:name)
      task_classes     = CbrainTask.descendants.map(&:name)

      raise "Error: cannot find any userfile subclasses?!?" if userfile_classes.blank?
      raise "Error: cannot find any task subclasses?!?"     if task_classes.blank?

      # NOTE: direct SQL is used here to avoid ActiveRecord throwing a SubclassNotFound exception on
      # every orphan.
      puts "Checking for orphan userfiles..."
      orphan_userfiles = Userfile.connection.execute("
        SELECT id, type
        FROM userfiles
        WHERE type NOT IN ('#{userfile_classes.join("','")}')
      ").to_a
      unless orphan_userfiles.empty?
        puts "#{orphan_userfiles.size} orphan userfile(s) found:"
        orphan_userfiles.each do |orphan|
          puts "-> id: #{orphan[0]}, type: #{orphan[1]}"
        end
      end

      puts "Checking for orphan tasks..."
      orphan_tasks = CbrainTask.connection.execute("
        SELECT id, type
        FROM cbrain_tasks
        WHERE type NOT IN ('#{task_classes.join("','")}')
      ").to_a
      unless orphan_tasks.empty?
        puts "#{orphan_tasks.size} orphan task(s) found:"
        orphan_tasks.each do |orphan|
          puts "-> id: #{orphan[0]}, type: #{orphan[1]}"
        end
      end

      if orphan_userfiles.empty? && orphan_tasks.empty?
        puts "No orphans (userfile or task) found."
      else
        puts "Please run 'rake cbrain:plugins:clean:orphans' to remove orphan tasks and userfiles."
      end
    end




    end # namespace check
  end # namespace plugins
end # namespace cbrain


