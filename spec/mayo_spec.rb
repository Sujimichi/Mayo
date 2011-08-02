require 'spec_helper'

describe Mayo do

  it 'should have tests' 

 
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

  end

end
