require 'spec_helper'
require 'fileutils'


class FakeThing
  def puts
    true
  end
  def gets
    {}.to_json
  end
end

describe Mayo do

  describe Mayo::Client do 


    describe "starting clients" do 
      before(:each) do 
        @dir = Dir.getwd
        begin
          Dir.mkdir("tmp")
        rescue
        end
        Dir.chdir("tmp")
        FileUtils.rm_rf("mayo_testing")
        f = FakeThing.new
        f.stub!(:register_with_server => nil)
        Mayo::Client.stub!(:new => f)
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
=begin
      it 'should create a directory for a client' do 
        Dir.entries("./").sort.should == [".", ".."]
        Mayo::Client.start
        Dir.entries("./").sort.should == [".", "..", "mayo_client_0"]
      end
      it 'should create a directory for each client' do 
        Dir.entries("./").sort.should == [".", ".."]
        Mayo::Client.start 3
        Dir.entries("./").sort.should == [".", "..", "mayo_client_0", "mayo_client_1", "mayo_client_2"]
      end
=end
    end

  end

=begin
  describe Mayo::Server do 
    before(:each) do 
      @s = Mayo::Server.new
    end

    it 'should have an empty array of clients' do 
      @s.clients.should be_empty  
    end

    describe "listen_for_clients" do 
      before(:each) do 
        @client = FakeThing.new
        @client.stub!(:puts => true)        
        @server = FakeThing.new
        @server.stub!(:accept => @client)
        TCPServer.stub!(:open => @server)
        @s.listen = true
        @s.listen_for_clients
      end
      after(:each) do 
        @s.listen = false
      end

      it 'should accept new clients connections and store them in @clients' do 
        @s.listen.should be_true
        @s.clients.should be_empty
        @server.should_receive(:accept).and_return(@client)
        @s.listen = false
        @client.should_receive(:gets).and_return({:some => :hash}.to_json)
        @s.clients.should_not be_empty
      end

    end

  end
=end
 
  describe "dividing tasks" do 

    before(:each) do       
       @s = Mayo::Server.new
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
