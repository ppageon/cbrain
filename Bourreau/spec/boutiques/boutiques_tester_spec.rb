#
# Bourreau-side tests for the Boutiques framework, using a mock tool (boutiquesTestApp.rb).
# Tests the generated cluster task by using it to create cluster commands that test against
# the mock tool and its expected output for each set of input parameters.
#

# Required files for inclusion
require 'rails_helper'
require 'spec_helper'
require_relative 'test_helpers'

# Add helper methods for performing tests
include TestHelpers

# Testing the Boutiques framework on the Bourreau side
describe "Bourreau Boutiques Tests" do

  # Run before block to create required input files
  before(:all) do
    FileUtils.touch('c')  # For -C
    FileUtils.touch('f')  # For -d
    FileUtils.touch('jf') # For -j
    [1,2].each { |i| FileUtils.touch("f#{i}") } # For -f
  end

  # Post-test cleanup via after block
  after(:all) do
    # Delete the input and output files when they exist
    ['c','f','jf','f1','f2'].each{ |f| File.delete(f) if File.exist?(f) }
    PotenOutFiles.each { |f| File.delete(f) if File.exist?(f) }
  end

  context "Cbrain external" do
    # Run before block to create ClusterTask object
    before(:each) do
      # Get the schema and json descriptor
      schema         = SchemaTaskGenerator.default_schema
      descriptor     = File.join(__dir__, TestScriptDescriptor)
      # Generate a new task class via the Boutiques framework and integrate it into cbrain
      @boutiquesTask = SchemaTaskGenerator.generate(schema, descriptor)
      @boutiquesTask.integrate if File.exists?(descriptor)
      # Create a new instance of the generated task class
      @task          = CbrainTask::BoutiquesTest.new
      @task.params   = {}
      # Give access to the generated task class itself
      @task_const    = "CbrainTask::#{SchemaTaskGenerator.classify(@task.name)}".constantize
    end

    # Tests expected behaviour of the auto-generated cluster task
    describe "Generated ClusterTask Object" do

      # Check necessary properties of the descriptor object
      describe "descriptor" do
        it "has the right name" do
          expect( @boutiquesTask.descriptor['name'] ).to eq( 'BoutiquesTest' )
        end
      end

      # Test some basic properties
      it "creates a tool" do
        expect( Tool.exists?( :cbrain_task_class => @task_const.to_s ) ).to be true
      end

      it "makes the tool accessible" do
        expect( @task_const.tool ).not_to be_nil
      end

      # Test that the apply_template method works as expected
      # for some representative (or previously buggy) cases
      describe "apply_template" do

        # Define some default parameters to use in the tests
        before(:each) do
          @template = 'cmd [1] [2] [3] [4] [5]'
          @def_keys = {'[1]' => 'one.txt', '[2]' => 2,             '[3]' => 't.csv', '[4]' => nil, '[5]' => nil}
          @flags    = {'[1]' => '-1',      '[2]' => '--long-flag', '[3]' => '-t',    '[4]' => nil, '[5]' => nil}
          @seps     = {'[1]' => '=',       '[2]' => '~',           '[3]' => ' ',     '[4]' => nil, '[5]' => nil}
        end

        it "handles string substitutions" do
          s = @task.apply_template(@template, @def_keys)
          expect( s.strip ).to eq( 'cmd one.txt 2 t.csv' )
        end

        it "handles string substituions with spaces" do
          s = @task.apply_template(@template, @def_keys.merge({'[4]' => '4 4'}))
          expect( s.strip ).to eq( "cmd one.txt 2 t.csv '4 4'" )
        end

        # Characters special to the shell or ruby's gsub should not interfere
        # In this case, ensure that ' is escaped properly
        it "handles special meaning characters" do
          s = @task.apply_template(@template, @def_keys.merge({'[4]' => " '; arg"}))
          expect( s.strip ).to eq( "cmd one.txt 2 t.csv ' '\\''; arg'" )
        end

        it "handles substitutions with command-line flags" do
          s = @task.apply_template(@template, @def_keys, flags: @flags)
          expect( s.strip ).to eq( "cmd -1 one.txt --long-flag 2 -t t.csv" )
        end

        it "handles substitution with flag-type inputs" do
          s = @task.apply_template(@template, @def_keys.merge({'[4]' => true}), flags: {'[4]' => '-f'})
          expect( s.strip ).to eq( "cmd one.txt 2 t.csv -f" )
        end

        it "handles special flag separator substitution" do
          s = @task.apply_template(@template,
                @def_keys.merge({'[4]' => true}),
                flags:      @flags.merge({'[4]' => '-f'}),
                separators: @seps)
          expect( s.strip ).to eq( "cmd -1=one.txt --long-flag~2 -t t.csv -f" )
        end

        it "properly strips endings" do
          s = @task.apply_template(@template,
                @def_keys.merge({'[4]' => true, '[5]' => '9.tex'}),
                flags:      @flags.merge({'[4]' => '-f', '[5]' => '-tex'}),
                separators: @seps,
                strip:      [ '.txt', '.tex' ])
          expect( s.strip ).to eq( "cmd -1=one --long-flag~2 -t t.csv -f -tex 9" )
        end

      end

      # Test that creating a basic cluster command in isolation works
      it "can create cluster commands" do
        @task.params[:A] = "A_VAL"
        expect( @task.cluster_commands[0].strip ).to eq( './' + TestScriptName + ' -A A_VAL' )
      end

    end

    # Testing Boutiques via the mock 'submission' of a local script, using the output of cluster_commands
    context 'Cluster Command Generation with Mock Program' do

      # After each local test, destroy the output files, so they don't interfere with downstream tests
      after(:each) do
        destroyOutputFiles
      end

      # Perform tests by running the cmd line given by cluster_commands and checking the exit code
      BasicTests.each do |test|
        # Testing for unrecognized inputs will not work here, since apply_template will ignore them
        next if test[0].include?( "unrecognized" )
        # The apply_template method adds the separator on its own, so we need only check that works
        next if test[0].include?( "fails when special separator" )
        # Run the test
        it "#{test[0]}" do
          # Convert string argument to params dict
          @task.params = ArgumentDictionary.( test[1] )
          # Run the generated command line from cluster_commands
          exit_code = runTestScript( @task.cluster_commands[0].gsub('./'+TestScriptName,''), test[3] || [] )
          # Check that the exit code is appropriate
          expect( exit_code ).to eq( test[2] )
        end
      end

    end
  end

  # Tests requiring complete Cbrain Bourreau-side system functionality
  describe 'Cbrain Internal' do

    # Test that the generated Boutiques task can handle output file saving and renaming
    # Mostly tests the autogenerated save_results method of the mock Boutiques task
    context 'Output File Handling' do

      # Define some useful constants (constants get redefined in before(:each) blocks)
      before(:all) do
        # The group, provider, and user ids used downstream
        GID, UID, DPID = Group.everyone.id, User.admin.id, 9
        # The warning message used when unable to find optional output files
        OptOutFileNotFoundWarning = "Unable to find optional output file: "
      end

      # Note: FactoryGirl methods should be used instead, but only if their db changes get rolled back in the before(:each) block
      # This is currently not happening, possibly due to some versioning issues
      before(:each) do
        # Destroy any pre-existing userfiles
        Userfile.all.each{ |uf| uf.destroy }
        # Create a mock task required output file
        @fname = DefReqOutName
        FileUtils.touch(@fname)
        # Helper method for getting filetype classes
        ftype = lambda { |fname| Userfile.suggested_file_type(fname) || SingleFile }
        @userfileClass = ftype.(@fname)
        # Get the schema and json descriptor
        descriptor     = File.join(__dir__, TestScriptDescriptor)
        # Generate a new task class via the Boutiques framework and integrate it into cbrain
        @boutiquesTask = SchemaTaskGenerator.generate(SchemaTaskGenerator.default_schema, descriptor)
        @boutiquesTask.integrate
        # Instantiate an object of the new class type
        @task          = CbrainTask::BoutiquesTest.new
        # Destroy any prior existing data providers (so we use a clean, lone one)
        DataProvider.all.each { |dp| dp.destroy }
        # Create a local data_provider to hold our files
        @provider      = FlatDirLocalDataProvider.new({ :online => true, :read_only => false, :remote_dir => '.' })
        @provider.id, @provider.name = DPID, 'test_provider'
        @provider.user_id, @provider.group_id = UID, GID
        @provider.save!
        # Add a local input file to the data provider (allows smarter lookup in userfile_exists)
        @file_c, @ft   = 'c', ftype.(@file_c)
        newFile = @task.safe_userfile_find_or_new(@ft, name: @file_c, data_provider_id: DPID, user_id: UID, group_id: GID)
        newFile.save!
        # Fill in data necessary for the task to check for and save the output file '@fname'
        @task.params   = {:ro => @fname, :interface_userfile_ids => [Userfile.all.first.id]}
        @task.user_id, @task.group_id = UID, GID
        # Generate a simulated exit file, as if the task had run
        @simExitFile   = @task.exit_cluster_filename
        FileUtils.touch( @simExitFile )
        # The basic properties for the required output file
        @reqOutfileProps = {:name => @fname, :data_provider_id => @provider.id}
        # Optional output file properties
        @optOutFileName  = OptOutName
        @optFileClass    = ftype.( @optOutFileName )
      end

      # Clean up after each test
      after(:each) do
        # Delete any generated output files
        destroyOutputFiles
        # Also need to get rid of the (simulated) exit file
        fename = '.qsub.exit.BoutiquesTest.-1'
        File.delete( fename ) if File.exists?( fename )
        # Destroy the registered userfiles and the data_provider, so as not to affect downstream tests
        # Necessary for tests that create and/or register userfiles in the it block
        Userfile.all.each{ |uf| uf.destroy }
        DataProvider.all.each { |dp| dp.destroy }
      end

      # Check that the input file could be properly registered
      it "has access to the registered input file" do
        expect( @task.userfile_exists( @ft, {:name => @file_c, :data_provider_id => @provider.id}) ).to be true
      end

      # Check that save_results works as expected for existent files
      it "can save results files" do
        # Make sure the file on the filesystem exists
        expect( File.exists? @fname ).to be true
        # Ensure the file has not been registered/created yet
        expect( @task.userfile_exists(@userfileClass, @reqOutfileProps) ).to be false
        # Ensure that saving the results occurs error-free
        expect( @task.save_results ).to be true
        # Ensure that the file now exists in the data_provider
        expect( @task.userfile_exists(@userfileClass, @reqOutfileProps) ).to be true
      end

      # Check that, when a required output file is not present, the task fails gracefully
      it "fails non-catastrophically when a required output file is not there" do
        # The output file should exist
        expect( File.exists? @fname ).to be true
        # Destroy the required output file
        File.delete( @fname )
        # Attempting to save_results should return a 'failure' error code
        expect( @task.save_results ).to be false
      end

      # Check that optional output files are saved appropriately
      it "handles optional output files when present" do
        # Create the optional output file
        FileUtils.touch( @optOutFileName )
        # Inform the generated task to look for the optional output file
        @task.params = @task.params.merge({:oo => @optOutFileName})
        # Ensure the file exists
        expect( File.exists? @optOutFileName ).to be true
        # Attempt to save both the optional and required output files. Should succeed.
        expect( @task.save_results ).to be true
        # Both files should exist in the data_provider
        expect( @task.userfile_exists(@userfileClass, @reqOutfileProps) ).to be true
        expect( @task.userfile_exists(@optFileClass,  {:name => @optOutFileName, :data_provider_id => @provider.id}) ).to be true
        # The log should not have warned about being unable to find the optional output file
        expect( @task.getlog.include?( OptOutFileNotFoundWarning + @optOutFileName ) ).to be false
      end

      # Check that there is no error when specified optional output files are not found
      # However, a logging should occur to note that fact
      it "handles absent optional output files properly" do
        # Inform the generated task to look for the optional output file
        @task.params = @task.params.merge({:oo => @optOutFileName})
        # Ensure the file does not exist
        expect( File.exists? @optOutFileName ).to be false
        # Attempt to save both the optional and required output files. Should succeed (in terms of return value).
        expect( @task.save_results ).to be true
        # Only the required file should exist in the data_provider
        expect( @task.userfile_exists(@userfileClass, @reqOutfileProps) ).to be true
        expect( @task.userfile_exists(@optFileClass,  {:name => @optOutFileName, :data_provider_id => @provider.id}) ).to be false
        # Check that a notice was logged to warn of the missing optional output file
        expect( @task.getlog.include?( OptOutFileNotFoundWarning + @optOutFileName ) ).to be true
      end

      # Ensure the files do not survive between tests
      it 'should destroy results files between tests' do
        expect( @task.userfile_exists(@userfileClass, @reqOutfileProps) ).to be false
      end

      # This test ensures that when a naming collision occurs, the second file is renamed appropriately
      it "renames results files" do
        # First ensure the file exists on the system
        expect( File.exists? @fname ).to be true
        # However, the file must not already exist in the data_provider
        expect( @task.userfile_exists(@userfileClass, @reqOutfileProps) ).to be false
        # Saving the output files via the generated task should occur error-free
        expect( @task.save_results ).to be true
        # The file should now exist in the data_provider
        expect( @task.userfile_exists(@userfileClass, @reqOutfileProps) ).to be true
        # Create a new task and have it save results as well (with the same name for the output file)
        task2        = CbrainTask::BoutiquesTest.new
        task2.params = {:ro => @fname, :interface_userfile_ids => [Userfile.all.first.id]}
        task2.user_id, task2.group_id = UID, GID
        # Check that there are no files that match the renamed filename pattern
        renamedFileRegex = /^#{@fname.split(".")[0]}-.*-\d{9}\.txt$/
        expect( Userfile.all.any? { |f| (f.name.to_s =~ renamedFileRegex) == 0 } ).to be false
        # Saving the second output file should be error free
        expect( task2.save_results ).to be true
        # Initial file should still be there with the correct, original name
        expect( @task.userfile_exists(@userfileClass, @reqOutfileProps) ).to be true
        expect( Userfile.where( :name => @fname ).first.nil? ).not_to be true
        # New file should exist and have been renamed appropriately
        expect( Userfile.all.one? { |f| (f.name.to_s =~ renamedFileRegex) == 0 } ).to be true
      end

    end # End output file handling tests

    # Test that a Tool Config is created iff both the bourreau and the descriptor specify docker
    context 'Default ToolConfig creation' do

      before(:each) do
        # Ensure the Bourreau does not have docker installed by default
        resource = RemoteResource.current_resource
        resource.docker_present = false
        resource.save!
        # Get the schema and json descriptor
        schema           = SchemaTaskGenerator.default_schema
        @descriptor      = File.join(__dir__, TestScriptDescriptor)
        # Generate a new task class via the Boutiques framework, without integrating it
        @boutiquesTask   = SchemaTaskGenerator.generate(schema, @descriptor)
        @boutiquesTask.descriptor["docker-image"] = nil # tool does not use docker by default
        @task_const_name = "CbrainTask::#{SchemaTaskGenerator.classify(@boutiquesTask.name)}"
        # Destroy any tools/toolconfigs for the tool, if any exist
        ToolConfig.where(tool_id: CbrainTask::BoutiquesTest.tool.id).destroy_all rescue nil
        Tool.where(:cbrain_task_class => @task_const_name).destroy_all rescue nil
      end

      after(:each) do
        # Destroy any tools/toolconfigs for the tool, if any exist
        ToolConfig.where(tool_id: @task_const_name.constantize.tool.id).destroy_all
        Tool.where(:cbrain_task_class => @task_const_name).destroy_all
        # Ensure the Bourreau does not have docker installed by default
        resource = RemoteResource.current_resource
        resource.docker_present = false
        resource.save!
      end

      it "is not done with only docker in task" do
        @boutiquesTask.descriptor['docker-image'] = 'placeholder_string'
        @boutiquesTask.integrate if File.exists?(@descriptor)
        expect( ToolConfig.exists?( :tool_id => @task_const_name.constantize.tool.id ) ).to be false
      end

      it "is not done with only docker in bourreau" do
        RemoteResource.current_resource.docker_present = true
        RemoteResource.current_resource.save!
        @boutiquesTask.integrate if File.exists?(@descriptor)
        expect( ToolConfig.exists?( :tool_id => @task_const_name.constantize.tool.id ) ).to be false
      end

      it "is done with docker in both task and bourreau" do
        @boutiquesTask.descriptor['docker-image'] = 'placeholder_string'
        resource       = RemoteResource.current_resource
        resource.docker_present = true
        resource.save!
        @boutiquesTask.integrate if File.exists?(@descriptor)
        expect( ToolConfig.exists?( :tool_id => @task_const_name.constantize.tool.id ) ).to be true
      end

      # When neither criteria is met, check that a ToolConfig is not made
      # Also checks that the integration changes were rolled back
      it "is not done without docker in task and bourreau" do
        @boutiquesTask.integrate if File.exists?(@descriptor)
        expect( ToolConfig.exists?( :tool_id => @task_const_name.constantize.tool.id ) ).to be false
      end

    end

  end

end

