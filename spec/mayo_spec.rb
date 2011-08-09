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
class FakeClient
end
describe Mayo do

  describe "having the TCP ports free to run tests!" do 
    ports = [:connect, :response , :instruction]
    ports.each do |port|
      it "should have port #{Mayo::PORTS[port]} open" do 
        begin
          server = TCPServer.open(Mayo::PORTS[port]) 
          server.close
        rescue
          raise "unable to use port #{Mayo::PORTS[port]}"
        end
      end
    end
  end

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

    def take_server_down t = "client"
      sleep 0.2 #to give previous intructions a chance to complete
      @server.instance_variable_get("@#{t}_server").close
      sleep 0.4 #to give the server time to close
      @threads.each{|t| t.kill}
    end

    describe "listen_for_clients" do
      before(:each) do 
        @server.instance_variable_set("@listen", true)
        @server.instance_variable_set("@project_dir", "/some_dir")
        @threads = []
        @threads << Thread.new {  @server.listen_for_clients  }
      end

      it 'should listen for a client connect and hold that clients info and socket' do 
        #simulate client action
        socket = TCPSocket.open(Socket.gethostname, Mayo::PORTS[:connect])
        socket.puts({:username => "foobar", :name => "yourface", :working_dir => "/here"}.to_json)

        take_server_down
        @server.clients.should_not be_empty
        @server.clients[0]["username"].should == "foobar"
        @server.clients[0]["socket"].should be_a(TCPSocket)
      end

      it 'should listen for multiple client connects' do 
        socket = TCPSocket.open(Socket.gethostname, Mayo::PORTS[:connect])
        socket.puts({:username => "foobar", :name => "yourface", :working_dir => "/here"}.to_json)
        socket = TCPSocket.open(Socket.gethostname, Mayo::PORTS[:connect])
        socket.puts({:username => "fibble", :name => "yourface", :working_dir => "/here"}.to_json)
       
        take_server_down       
        @server.clients.should_not be_empty
        @server.clients[0]["username"].should == "foobar"
        @server.clients[1]["username"].should == "fibble"
      end

      it 'should listen for symultanious multiple client connects' do
        threads = []
        threads << Thread.new{
          socket = TCPSocket.open(Socket.gethostname, Mayo::PORTS[:connect])
          socket.puts({:username => "foobar", :name => "yourface", :working_dir => "/here"}.to_json)
        }
        threads << Thread.new {
          socket = TCPSocket.open(Socket.gethostname, Mayo::PORTS[:connect])
          socket.puts({:username => "fibble", :name => "yourface", :working_dir => "/here"}.to_json)
        }
        threads.each{|t| t.join}
        take_server_down              
        @server.clients.size.should == 2
        @server.clients.map{|c| c["username"]}.sort.should == ["foobar", "fibble"].sort
      end

      it 'should provide the client with info about the server' do 
        socket = TCPSocket.open(Socket.gethostname, Mayo::PORTS[:connect])
        r = socket.gets
        take_server_down
        r.chop.should == {:project_dir => "/some_dir", :servername => Socket.gethostname}.to_json
      end
 
    end

    describe "listen_for_response" do 
      before(:each) do 
        @server.instance_variable_set("@listen", true)
        @server.instance_variable_set("@project_dir", "/some_dir")
        @threads = []
        @threads << Thread.new {  @server.listen_for_response  }
      end
      it 'should take info from clients and put it in @results' do 
        @server.instance_variable_get("@results").should be_empty
        socket = TCPSocket.open(Socket.gethostname, Mayo::PORTS[:response])
        r = socket.puts("this is a test\nwith some multiline data")
        socket.close
        take_server_down("response")
        @server.instance_variable_get("@results")[0].should == ["this is a test", "with some multiline data"]
      end

      it 'should take info from two clients responding at the same time' do 
        Thread.new{
          socket = TCPSocket.open(Socket.gethostname, Mayo::PORTS[:response])
          r = socket.puts("this is one client\nwith some multiline data")
          socket.close
        } 
        Thread.new {
          socket = TCPSocket.open(Socket.gethostname, Mayo::PORTS[:response])
          r = socket.puts("this is another client\nalso with some data")
          socket.close
        }
        take_server_down("response")       
        r = [["this is one client", "with some multiline data"], ["this is another client", "also with some data"]]
        @server.instance_variable_get("@results").sort.should == r.sort
      end


    end


    describe "listen_for_intructions" do 
      it 'should have some tests to describe listening for instructions' 
    end

    describe "perform(instruction)" do
      before(:each) do 
        @job = Mayo::Job.new("features", ["feature1.feature", "feature2.feature"])
        @server.stub!(:current_clients => ["foo", "bar"])
        @server.stub!(:make_job => @job)
        @server.stub!(:process_job => nil)
        @server.stub!(:update_active_clients => nil)        
      end

      it 'should call stop on the server' do 
        @server.should_receive(:stop)
        @server.perform("stop")
      end

      it "should call make job with just 'run'" do 
        @server.should_receive(:make_job)
        @server.perform("run")
      end
      it 'should call make_jobs with args' do 
        @server.should_receive(:make_job).with("features", "features/*3/*.feature")
        @server.perform(["run", "features", "features/*3/*.feature"])
      end
      it 'should call make job with args' do 
        @server.should_receive(:make_job).with("specs")
        @server.perform(["run", "specs"])
      end

      it 'should call update active clients' do 
        @server.should_receive(:update_active_clients)        
        @server.perform(["run", "specs"])
      end

      it 'should call process_job with the job returned by make_job' do 
        @server.should_receive(:process_job).with(@job, ["foo", "bar"])
        @server.perform(["run", "features"])
      end

      it 'should not call process_job when the job is a string, it should display it' do 
        @server.stub!(:make_job => "some error message")
        @server.should_not_receive(:process_job)
        @server.should_receive(:puts).once.with("some error message")
        @server.should_receive(:puts) #as it will also receive puts elsewhere
        @server.perform(["run", "last_failed"])
      end

    end
    describe "perform(intructions) when there are no clients" do 
      before(:each) do 
        @server.stub!(:current_clients => [])
      end
      it 'should not call update_active_clients' do 
        @server.should_not_receive(:update_active_clients)        
        @server.perform(["run", "specs"])
      end
      it 'should not call update_active_clients' do 
        @server.should_not_receive(:process_job)        
        @server.perform(["run", "specs"])
      end
      
    end


    describe "make_job" do 
      before(:each) do
        @files = ["this.file", "that.file"]
      end

      it 'should return a Mayo::Job' do 
        @server.stub!(:get_files_from => @files)
        job = @server.make_job(["specs"])
        job.should be_a(Mayo::Job)
      end

      it 'should send a type and auto selected Spec files to Mayo::Job.new' do        
        Mayo::Job.should_receive(:new).with("specs", @files)
        @server.should_receive(:get_files_from).with("spec/**/*spec.rb").and_return(@files)
        @server.make_job("specs")
      end

      it 'should send a type and auto selected Feature files to Mayo::Job.new' do        
        Mayo::Job.should_receive(:new).with("features", @files)
        @server.should_receive(:features_by_scenario).and_return(@files)
        @server.should_receive(:get_files_from).with("features/**/*.feature").and_return(@files)
        @server.make_job("features")
      end

      it 'should send type and files (passed in as string) to Mayo::Job.new' do 
        @server.should_receive(:get_files_from).with("my_random.file", "my_linear.file").and_return(["my_random.file", "my_linear.file"]) #essentiall just passes thou
        Mayo::Job.should_receive(:new).with("specs", ["my_random.file", "my_linear.file"])
        @server.make_job(*["specs", "my_random.file my_linear.file"])
      end

      it 'should pass type and files (passed in as *args) onto Mayo::Job.new' do 
        Mayo::Job.should_receive(:new).with("specs", ["my_random.file", "my_linear.file"])
        @server.should_not_receive(:get_files_from)
        @server.make_job(*["specs", "my_random.file", "my_linear.file"] )
      end

      it "should return a 're_run_job'" do 
        re_run_job = Mayo::Job.new("features", ["failed_thing.file", "other_failed_thing.file"])
        @server.instance_variable_set("@re_run_job", re_run_job)
        job = @server.make_job(*["run", "last_failed"] )
        job.should == re_run_job
        Mayo::Job.should_not_receive(:new)
      end

      it 'should return a string message if no re_run_job' do 
        job = @server.make_job(*["run", "last_failed"] )
        job.should be_a(String)
        job.downcase.should be_include("no re run job")
      end

    end

    describe "process_job" do 
      before(:each) do 
        files = ["thishere.file", "thatthar.file"]
        files.should_receive(:sort_by).and_return(files) #disable the sort by rand which is done to the files passed into Mayo::Job.new
        @job = Mayo::Job.new("features", files)
        @client_1 = {"socket" => FakeSocket.new}
        @client_2 = {"socket" => FakeSocket.new}       
        @clients = [ @client_1, @client_2 ]
      end

      it 'should call each client supplied with a socket instuction' do       
        @client_1["socket"].should_receive(:puts).once.with("{\"run_and_return\":\"bundle exec cucumber -p all features/support/ features/step_definitions/ thatthar.file\"}")
        @client_2["socket"].should_receive(:puts).once.with("{\"run_and_return\":\"bundle exec cucumber -p all features/support/ features/step_definitions/ thishere.file\"}")
        @server.process_job @job, @clients
      end

      it 'should not call excess clients with any command' do 
        @client_3 = {"socket" => FakeSocket.new}       
        @clients = [ @client_1, @client_2, @client_3 ]
        @client_1["socket"].should_receive(:puts).once.with("{\"run_and_return\":\"bundle exec cucumber -p all features/support/ features/step_definitions/ thatthar.file\"}")
        @client_2["socket"].should_receive(:puts).once.with("{\"run_and_return\":\"bundle exec cucumber -p all features/support/ features/step_definitions/ thishere.file\"}")
        @client_3["socket"].should_not_receive(:puts)
        @server.process_job @job, @clients
      end
    end
  end

  describe Mayo::Job do 

    #Mayo::Job.new("features")
    #Mayo::Job.new("features", "features/dir/feature.feature:5 features/dir/feature.feature:42")
    #Mayo::Job.new("bundle exec cucumber -p all", "features/dir/feature.feature:5 features/dir/feature.feature:42")
    #Mayo::Job.new("bundle exec rspec", "spec/models/entity_spec.rb spec/models/moo_spec.rb")
    
    it "should have a mapping for the launcher arg 'features'" do 
      @job = Mayo::Job.new("features", ["features/dir/feature.feature:5", "features/dir/feature.feature:42", "features/dir/feature.feature:64"])
      @job.launcher.should == "bundle exec cucumber -p all features/support/ features/step_definitions/"
    end

    it "should have a mapping for the launcher arg 'specs'" do 
      @job = Mayo::Job.new("specs", ["some.file", "some_other.file", "yet_another.file"])
      @job.launcher.should == "bundle exec rspec"
    end
  
    it "should pass on any other launcher arg " do 
      @job = Mayo::Job.new("bundle exec ruby")
      @job.launcher.should == "bundle exec ruby"
    end

    describe "in_groups_of(n) - with rand disabled" do
      before(:each) do
        files = ["some.file", "some_other.file", "yet_another.file"]
        files.should_receive(:sort_by).and_return(files)
        @job = Mayo::Job.new("some exec command", files)
      end
      it "should divide ordnance into 2 groups and prefex each group with the launcher" do 
        @job.in_groups_of(2).should == [
          "some exec command yet_another.file some.file",
          "some exec command some_other.file"
        ]
      end
      it "should divide ordnance into 2 groups and prefex each group with the launcher" do 
        @job.in_groups_of(3).should == [
          "some exec command yet_another.file",
          "some exec command some_other.file", 
          "some exec command some.file"
        ]
      end
      it "should divide ordnance into 2 groups and prefex each group with the launcher" do 
        @job.in_groups_of(4).should == [
          "some exec command yet_another.file",
          "some exec command some_other.file", 
          "some exec command some.file",
          nil
        ]
      end
    end 

    describe "in_groups_of(n) - with rand" do             #This test has a chance of failing
      before(:each) do                                    #its aim is to test that the given array of files 
        files = %w[foo bar dar mar gar tar lar far nar]   #get randomly sorted.  Therefore the output of two 
        @job = Mayo::Job.new("some exec command", files)  #concecutive calls should not ==.  Except when rand is
      end                                                 #randomly the same in each case.
      it 'should randomize the tasks' do 
        g1 = @job.in_groups_of(3)
        g2 = @job.in_groups_of(3)
        g1.should_not == g2
      end     
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
        @socket.should_receive(:puts).with("Result from #{Socket.gethostname}\nresult_data")
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
