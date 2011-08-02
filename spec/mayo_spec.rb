require 'spec_helper'

describe Mayo do

  it 'should have tests' 

  describe Mayo::Server do 

    it 'should wait for clients to connect and then have a list of clients' do 
      s = Mayo::Server.new
      s.clients.should be empty?

      sleep 2
      c1 = Mayo::Client.new
      c2 = Mayo::Client.new
      c1.should_receive(:client_name).once.and_return("jim")
      c2.should_receive(:client_name).once.and_return("jan")

      s.clients.size.should == 2


    end

  end

end
