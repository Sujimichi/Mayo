module Mayo
  def self.command args
    Mayo::Server.start if args.include?("server")
    Mayo::Server.run   if args.include?("run")
    Mayo::Server.stop   if args.include?("stop")
    
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

  def self.run
    @cache = Dalli::Client.new('localhost:11211')   
    @cache.set("mayo_instruction", "go nuts")
  end

  def self.stop
    @cache = Dalli::Client.new('localhost:11211')   
    @cache.set("mayo_instruction", "stop")
  end

  attr_accessor :clients

  def initialize
    puts "Initializing Mayo Server - The Rich Creamy Goodness of your tests will soon be spread."
    @cache = Dalli::Client.new('localhost:11211')   
    @project_dir = Dir.getwd
    
    @clients = []
    @active_clients = []
    @threads = []

    @threads << Thread.new { wait_for_clients }

    @cache.set("mayo_instruction", nil)
    order = nil
    last_order = nil
    puts "waiting for orders"     
    while order != "stop"
      order = @cache.get("mayo_instruction")
      @cache.set("mayo_instruction", nil)
      if order && order != last_order
        puts "got order: #{order}"
        last_order = order
      end
    end
    self.stop
  end

  def do_stuff
    #@cache.set("active_mayo_server", self)
    puts "sleeping"
    sleep 5

    puts current_clients.inspect
    instruct_clients current_clients
  end

  def stop
    puts "Shutting down"
    @threads.each{|thread| thread.kill}
  end

  def wait_for_clients
    server = TCPServer.open(2000)   
    
    loop {
      print "."
      #Thread.start(server.accept) do |client|
        client = server.accept
        client.puts({:project_dir => @project_dir}.to_json) #Send data to client       
        client_data = client.gets # Read info from client       
        client_data = JSON.parse(client_data)
        client_data["socket"] = client
        @clients << client_data
        puts "Signing up new client: #{client_data['name']}"       
        send_files_to_client(client_data)

        #client.close                
      #end
    }
  end

  def send_files_to_client client_data
    command = "rsync -avc -e ssh --delete --ignore-errors #{@project_dir} #{client_data["username"]}@#{client_data["name"]}:#{client_data["working_dir"]}"
    `#{command}`
  end

  def current_clients
    @clients.select{|c| 
      begin  
        s = c["socket"]
        s.puts("respond")
        s.gets.chomp.eql?("alive")
      rescue
        false
      end
    }
  end

  def instruct_clients clients
    instructions = %w[party do_action]
    clients.each_with_index do |c, i|
      c = c["socket"]
      c.puts "fuck you"
      c.puts instructions[i]
      c.close
    end
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

    @client_data = {:username => "sujimichi", :name => client_name, :working_dir => Dir.getwd}
    register_with_server  
    puts @project_dir.inspect
  end

  def register_with_server
    @socket = TCPSocket.open(@server, @server_port)
    @socket.puts(@client_data.to_json)
    @server_inf = JSON.parse(@socket.gets)
    #@socket.close
    @project_dir = @server_inf["project_dir"]
    order = true
    while !order.nil?
      begin
      order = @socket.gets   # Read lines from the socket
      rescue
        order = nil
      end
      follow_orders order.chomp if order
    end
  end

  def follow_orders order
    puts "GOT ORDER #{order}"
    case order

    when "stop"
      puts "shutting down"
      @socket.close
    when "respond"
      @socket.puts("alive")
    when "party"
      puts "WOOOOOOO"
    when "do_action"
      command = "gedit"
      system command
    else
      puts "WHAT? Server is talking rubbish \"#{order}\""
    end
  end

  def client_name
    Socket.gethostname
  end

end

