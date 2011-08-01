module Mayo
  def self.command args
    Mayo::Server.start if args.include?("server")
    Mayo::Client.start if args.include?("connect")
  end
end


class Mayo::Server
  require 'socket'
  require 'dalli'
  require 'json'

  def self.start   
    server = Mayo::Server.new
  end

  def initialize
    @project_dir = Dir.getwd
    @cache = Dalli::Client.new('localhost:11211')   

    @clients = []

    @cache.set('abc', 123)
    value = @cache.get('abc')
    puts value.inspect
    wait_for_clients
    puts "next"
    #@cache.set("active_mayo_server", self)
    current_clients
  end

  def wait_for_clients
    server = TCPServer.open(2000)   
    @cache.set('count', 0)    
    
    2.times {
      print "."
      Thread.start(server.accept) do |client|
        puts "Signing up new client:"

        client.puts({:project_dir => @project_dir}.to_json) #Send data to client       
        client_data = client.gets # Read info from client
        
        print "\t#{client_data}"
        i = @cache.get('count')        
        @cache.set("client_#{i}", client_data)
        
        send_files_to_client JSON.parse(client_data)  
        client.close                
      end
    }
  end

  def send_files_to_client client_data
    command = "rsync -avc -e ssh --delete --ignore-errors #{@project_dir} #{client_data["username"]}@#{client_data["hostname"]}:#{client_data["working_dir"]}"
    `#{command}`
  end

  def current_clients
    puts "looking for clients in cache"
    @current_clients = []
    i = 0
    stop = false
    until stop
      client_data = @cache.get("client_#{i}")
      stop = client_data.nil?
      puts "putsing"
      puts i
      puts client_data.inspect
      @current_clients << client_data
      i += 1
      raise "wft" if i >= 50
    end

    puts @current_clients.inspect
  end

end

class Mayo::Client
  require 'socket'
  require 'json'

  def self.start
    c = Mayo::Client.new
  end

  def initialize
    @server = 'localhost'
    @server_port = 2000

    begin
      Dir.mkdir("tmp_testing")
    rescue
    end
    Dir.chdir("tmp_testing")

    @client_data = {:username => "sujimichi", :hostname => Socket.gethostname, :working_dir => Dir.getwd}
    register_with_server  
    puts @project_dir.inspect
  end

  def register_with_server
    @socket = TCPSocket.open(@server, @server_port)
    @socket.puts(@client_data.to_json)
    @server_inf = JSON.parse(@socket.gets)
    @socket.close
    @project_dir = @server_inf["project_dir"]
    
  end

end

