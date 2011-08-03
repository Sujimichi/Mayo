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

describe Mayo do

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

  describe Mayo::Server do 
    before(:each) do 
      @server = @s = Mayo::Server.new
    end

    describe "listen_for_intructions" do 
      before(:each) do 
        @cache = Dalli::Client.new('localhost:11211')   
      end

      it 'should call perform with the intruction' do 
        @cache.set("mayo_instruction", "test_instruction")
        @server.should_receive(:perform).with("test_instruction")
        @server.listen_for_instructions
        @cache.set("mayo_instruction", "stop")
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
end
