require 'spec_helper'
require 'fileutils'

class FakeSocket
  def puts s
  end
  def gets
  end
  def close
  end
end
class FakeServer

end

describe Mayo do

  describe "self.commands" do 
    it 'should call start on the server' do 
      Mayo::Server.should_receive(:start).and_return(nil)
      Mayo.command "server"
    end
    it 'should call start on the client' do 
      Mayo::Client.should_receive(:start).and_return(nil)
      Mayo.command "connect"
    end

    it 'should call run on the server and pass arguments' do 
      args = ["run", "this_thing"]
      Mayo::Server.should_receive(:run).with(args).and_return(nil)      
      Mayo.command args
    end
    it 'should call stop on the server' do 
      Mayo::Server.should_receive(:stop).and_return(nil)      
      Mayo.command "stop"
    end
  end

  describe Mayo::Server do 
    before(:each) do 
      @server = @s = Mayo::Server.new
    end

    describe "self methods" do 
      before(:each) do 
        @socket = FakeSocket.new
        TCPSocket.should_receive(:open).with(Socket.gethostname, Mayo::PORTS[:instruction]).and_return(@socket)
      end
      
      describe "self.start" do 
        it 'should start the server'
      end

      describe "self.stop" do 
        it 'should stop the server' do 
          @socket.should_receive(:puts).with("stop")
          Mayo::Server.stop
        end

      end
      describe "self.run" do 
        it 'should run the server' do 
          @socket.should_receive(:puts).with("run")
          Mayo::Server.run
        end
        it 'should run the server with args' do 
          @socket.should_receive(:puts).with(["run", "arg1", "arg2"])
          Mayo::Server.run "run", "arg1", "arg2"
        end

      end

    end
    describe "listen_for_intructions" do 
      it 'should have some tests to describe listening for instructions' 

    end

    describe "perform(instruction)" do 

      it 'should call stop on the server' do 
        @server.should_receive(:stop)
        @server.perform("stop")
      end

      it 'should call run tests' do 
        args = ["run", "features", "features/*3/*.feature"]
        @server.should_receive(:run_tests)
        @server.perform("run")
      end

      it 'should call run tests with args' do 
        args = ["run", "features", "features/*3/*.feature"]
        @server.should_receive(:run_tests).with("features", "features/*3/*.feature")
        @server.perform(args)
      end

      it 'should call run tests with args' do 
        args = ["run", "specs"]
        @server.should_receive(:run_tests).with("specs")
        @server.perform(args)
      end

    end


    describe "run tests" do 
      before(:each) do 
        @client1 = {"socket" => FakeSocket.new}
        @client2 = {"socket" => FakeSocket.new}
        @server.stub!(:current_clients => [@client1, @client2])
        @files = ["some_dir/some_file_1.file", "some_dir/some_file_2.file", "some_dir/some_file_3.file"]
        @files.stub!(:sort_by => @files) #disable the sort by random
        @server.should_receive(:update_active_clients).and_return(nil)
        @server.stub!(:features_by_scenario => [])
      end
        #command = "bundle exec cucumber -p all features/support/ features/step_definitions/ some_dir/some_file_3.file some_dir/some_file_2.file some_dir/some_file_1.file"
        #@client["socket"].should_receive(:puts).with({"run_and_return" => command}.to_json)

      it "can be called with no args to load features" do 
        @server.should_receive(:get_files_from).with("features/**/*.feature").and_return(@files)
        @server.run_tests "features"
      end

      it "can be called with 'specs' to load specs" do 
        @server.should_receive(:get_files_from).with("spec/**/*spec.rb").and_return(@files)
        @server.run_tests "specs"
      end

      it "can be called with 'features and paths' to load specific specific features" do 
        @server.should_receive(:get_files_from).with("features/03*/*.feature").and_return(@files)
        @server.run_tests "features", "features/03*/*.feature"
      end

      it "can be called with 'features and paths' to load specific a specific feature" do 
        @server.should_receive(:get_files_from).with("features/thisdir/that.feature", "features/thisdir/this.feature").and_return(@files)
        @server.run_tests "features", "features/thisdir/that.feature features/thisdir/this.feature"
      end

      it 'should send both clients the first arg and split the files (2nd arg) between them' do 
        command1 = "with_this_executable run_this/file.rb"
        command2 = "with_this_executable and_this/other_file.rb"
        @client1["socket"].should_receive(:puts).with({"run_and_return" => command1}.to_json)
        @client2["socket"].should_receive(:puts).with({"run_and_return" => command2}.to_json)
        @files = ["run_this/file.rb", "and_this/other_file.rb"]
        @files.stub!(:sort_by => @files.reverse) #disable the sort by random, and reverse to account for the use of array.pop. otherwise client1 => command2, client2 => command1.  Just for testing layout, normaly its randomized so is not important.
        @server.should_receive(:get_files_from).with("run_this/file.rb", "and_this/other_file.rb").and_return(@files)
        @server.run_tests "with_this_executable", "run_this/file.rb and_this/other_file.rb"
      end

      it 'should send both clients spec instructions and a split of the files' do 
        command1 = "bundle exec rspec spec/file_spec.rb spec/yet_other_file_spec.rb"
        command2 = "bundle exec rspec spec/other_file_spec.rb"
        @client1["socket"].should_receive(:puts).with({"run_and_return" => command1}.to_json)
        @client2["socket"].should_receive(:puts).with({"run_and_return" => command2}.to_json)
        @files = ["spec/file_spec.rb", "spec/other_file_spec.rb", "spec/yet_other_file_spec.rb"]
        @files.stub!(:sort_by => @files.reverse) 
        @server.should_receive(:get_files_from).with("spec/**/*spec.rb").and_return(@files)
        @server.run_tests "specs"
      end

      it 'should send both clients feature instructions and a split of the files, split by scenario' do 
        feature_pre = "bundle exec cucumber -p all features/support/ features/step_definitions/"
        command1 = "#{feature_pre} features/thing.feature:1 features/yet_other.feature:1 features/daft.feature:1"
        command2 = "#{feature_pre} features/thing.feature:4 features/yet_other.feature:8 features/daft.feature:12"
        @client1["socket"].should_receive(:puts).with({"run_and_return" => command1}.to_json)
        @client2["socket"].should_receive(:puts).with({"run_and_return" => command2}.to_json)
        @files = ["spec/file_spec.rb", "spec/other_file_spec.rb", "spec/yet_other_file_spec.rb"]
        @server.should_receive(:get_files_from).with("features/**/*.feature").and_return(@files)
        @files.stub!(:sort_by => @files.reverse) 


        features = ["features/thing.feature:1", "features/thing.feature:4", "features/yet_other.feature:1", "features/yet_other.feature:8", "features/daft.feature:1", "features/daft.feature:12"]
        features.stub!(:sort_by => features.reverse) 
        @server.should_receive(:features_by_scenario).with(@files).and_return(features)
        
        @server.run_tests "features"
      end





      it 'can be called' do
        @server.should_receive(:get_files_from).with("features/thisdir/that.feature", "features/thisdir/this.feature").and_return(@files)
        @server.run_tests "bundle exec cucumber", "features/thisdir/that.feature features/thisdir/this.feature"
      end


      #mayo run
      #mayo run features
      #mayo run specs
      #mayo run features features/03*/*.feature
      #mayo run ruby "tasks/thing.rb tasks/otherthing.rb"


    end

    
    describe "run tests (when no clients)" do 
      it 'should not call update_active_clients' do 
        @server.should_not_receive(:active_clients)
        @server.should_not_receive(:get_files_from)
        @server.stub!(:current_clients => [])
        @server.run_tests
      end
    end
    describe "dividing tasks" do 

      before(:each) do       
        @s.stub!(:current_clients => Array.new(3))
      end

      it 'should divide tasks into as many arrays as there are clients' do 
        tasks = %w[foo bar lar dar tar mar rar]     
        @s.stub!(:current_clients => Array.new(4))
        groups = @s.divide_tasks tasks
        groups.size.should == 4
        groups.map{|g| g.size}.should == [2,2,2,1]

        @s.stub!(:current_clients => Array.new(3))
        groups = @s.divide_tasks tasks
        groups.size.should == 3
        groups.map{|g| g.size}.should == [3,2,2]

        @s.stub!(:current_clients => Array.new(2))
        groups = @s.divide_tasks tasks
        groups.size.should == 2
        groups.map{|g| g.size}.should == [4,3]
      end

      it 'should randomize the tasks' do 
        tasks = %w[foo bar lar dar tar mar rar]     
        @s.stub!(:current_clients => Array.new(4))
        g1 = @s.divide_tasks tasks
        g2 = @s.divide_tasks tasks
        g1.size.should == 4
        g2.size.should == 4
        g1.should_not == g2
      end

    end
  end

  describe Mayo::Task do 
    it 'should return a custom class for features' do 
      Mayo::Task.for_type("features").should be_a(FeatureTask)
    end
    it 'should return a custom class for specs' do 
      Mayo::Task.for_type("specs").should be_a(SpecTask)
    end
    it 'should return the base class for everything else' do 
      Mayo::Task.for_type("youfatuncle").should be_a(Mayo::Task)
    end



  end

  describe Mayo::Client do 


    describe "starting clients" do 
      before(:each) do 
        @dir = Dir.getwd
        Dir.mkdir("tmp") unless Dir.entries("./").include?("tmp")
        Dir.chdir("tmp")
        FileUtils.rm_rf("mayo_testing")
        f = Mayo::Client.new
        f.should_receive(:register_with_server).once
        f.should_receive(:wait_for_orders).once
        Mayo::Client.should_receive(:new).and_return(f)
      end
      after(:each) do 
        Dir.chdir(@dir)
      end

      it 'should create a mayo_testing folder to work in' do 
        Mayo::Client.start
        Dir.getwd.should == @dir + "/tmp/mayo_testing"
      end

      it 'should use one if already present' do 
        Dir.mkdir("mayo_testing")
        Mayo::Client.start
        Dir.getwd.should == @dir + "/tmp/mayo_testing"
      end

    end

    describe "register with server" do 
      before(:each) do 
        @socket = FakeSocket.new
        data_sent_from_server = {:project_dir => "/somedir/test_project", :servername => "someserver"}
        @socket.should_receive(:gets).and_return(data_sent_from_server.to_json)
        TCPSocket.stub!(:open => @socket)
        @client = Mayo::Client.new
        @client.instance_variable_get("@server_inf").should be_nil

      end

      it 'should obtain information from the socket' do 
        @client.register_with_server       
        @client.instance_variable_get("@server_inf").should_not be_nil
      end

      it 'should get the project name' do 
        @client.register_with_server       
        @client.instance_variable_get("@server_inf")["project_dir"].should == "/somedir/test_project"
        @client.instance_variable_get("@project_name").should == "test_project"
      end

      it 'should get the server name' do 
        @client.register_with_server       
        @client.instance_variable_get("@server_inf")["servername"].should == "someserver"
      end

      it 'should send data to the server' do 
        @client.instance_variable_get("@client_data").should_not be_nil
        cd = @client.instance_variable_get("@client_data")
        @socket.should_receive(:puts).with(cd.to_json)
        @client.register_with_server       
      end

    end

    describe "wait_for_orders" do 
      before(:each) do 
        @socket = FakeSocket.new
        @client = Mayo::Client.new
        @client.instance_variable_set("@socket", @socket)       
      end

      it 'should call follow orders with the info from the server' do 
        @socket.should_receive(:gets).once.and_return("test_command") #simulated command from server
        @socket.should_receive(:gets).once.and_return(nil)            #simulated disconect (otherwise it will keep waiting)
        @client.should_receive(:follow_orders).with("test_command")
        @client.wait_for_orders
      end

    end

    describe "follow_orders" do 
      before(:each) do 
        @socket = FakeSocket.new
        TCPSocket.stub!(:open => @socket)
        @client = Mayo::Client.new
        @client.instance_variable_set("@socket", @socket)       
      end

      it 'should close the socket' do 
        @socket.should_receive(:close)
        @client.follow_orders("stop")
      end

      it 'should move into the project dir' do 
        init_dir = Dir.getwd
        FileUtils.rm_rf("test_project")        
        Dir.mkdir("test_project")
        @client.instance_variable_set("@project_dir", init_dir + "/test_project")
        @client.follow_orders("goto_project_dir")       
        Dir.getwd.should ==  init_dir + "/test_project"  #assert that the working dir is now the project dir
        Dir.chdir(init_dir) #go back to initial dir to reset the test.
      end


      it "should take json hash orders to be 'run'" do 
        @client.should_receive(:run_command).with("some command")
        @client.follow_orders({"run" => "some command"}.to_json)
      end

      it "should take json hash orders to be 'run and returned'" do 
        @client.should_receive(:run_command).with("some command")
        @client.follow_orders({"run_and_return" => "some command"}.to_json)
      end

      it "should return command results to the server" do 
        @client.should_receive(:run_command).with("some command").and_return("result_data")
        @socket.should_receive(:puts).with("result_data")
        @socket.should_receive(:close)       
        @client.follow_orders({"run_and_return" => "some command"}.to_json)
      end


    end

    describe "run_command" do 
      before(:each) do 
        @client = Mayo::Client.new
      end

      it "should run have some tests that make assertions about backticks!"

    end
  end
end
