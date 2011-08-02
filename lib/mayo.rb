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
    @cache.set("mayo_instruction", "run")
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
    @threads = [ Thread.new { wait_for_clients } ]  #Create a background thread which accepts connections from new clients
    listen_for_intructions #listen for instrunctions sent via memcached 
  end

  def wait_for_clients
    server = TCPServer.open(2000)
    puts "Ready to accept clients"
    loop {
      client = server.accept
      client.puts({:project_dir => @project_dir, :servername => Socket.gethostname}.to_json) #Send data to client       
      client_data = client.gets # Read info from client       
      client_data = JSON.parse(client_data).merge!("socket" => client)
      @clients << client_data
      puts "Signing up client: #{client_data['name']}"       
    }
  end

  def listen_for_intructions
    @cache.set("mayo_instruction", nil) #make sure no old instruction
    puts "waiting for orders"     
    while @cache.get("mayo_instruction").nil?
    end
    self.perform(@cache.get("mayo_instruction"))
    @cache.set("mayo_instruction", nil)     #reset cache
  end

  def perform order
    puts "got order: #{order}"
    case order
    when "run"
      run_features
    when "stop"
      return self.stop
    end
    listen_for_intructions
  end

  def run_specs
    update_active_clients
    specs = Dir['spec/**/*spec.rb']
    specs = ["spec/lib/vr_xml_acceptance_spec.rb", "spec/models/entity_spec.rb"]

    active_clients do |client, index|
      command = "bundle exec rspec #{specs[index]}"
      client["socket"].puts({:run => command}.to_json)
    end
  end

  def run_features
    update_active_clients
    specs = Dir['features/**/*.feature']

    active_clients do |client, index|
      command = "bundle exec cucumber features/support/ features/step_definitions/ #{specs[index]}"
      client["socket"].puts({:run => command}.to_json)
    end

  end


  def update_active_clients
    print "\nUpdating Active Clients' Data"
    c = 0
    active_clients do |client|
      print(".")
      client["socket"].puts({:display => "receiving files"}.to_json)
      send_files_to_client client
      client["socket"].puts("goto_project_dir")
      c += 1
    end
    puts "updated #{c} clients"
  end

  def stop
    puts "Shutting down"
    active_clients{|c| 
      c["socket"].puts({:display => "got kill message"}.to_json) 
      c["socket"].close
    }
    @threads.each{|thread| thread.kill}
  end

  def send_files_to_client client_data
    command = "rsync -avc -e ssh --delete --ignore-errors #{@project_dir} #{client_data["username"]}@#{client_data["name"]}:#{client_data["working_dir"]}"
    `#{command}`
  end

  def active_clients &blk
    current_clients.each_with_index do |client, index|
      yield(client, index)      
    end
  end

  #Quick and Dirty Discovery of which clients are still connected and alive
  def current_clients
    @clients.select{|c| #Select the clients which respond
      begin  
        c["socket"].puts("respond") #If the client has disconected this line will throw exception
        true
      rescue
        false
      end
    }
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
    @project_name = @server_inf["project_dir"].split("/").last
    @project_dir = Dir.getwd + "/" + @project_name

    puts "Registered with Mayo Server #{@server_inf["servername"]} for project #{@project_name}"
    
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
    when "goto_project_dir"
      Dir.chdir(@project_dir)
      puts "now in #{Dir.getwd}"
    else
      begin
        order = JSON.parse(order)
        if order.keys[0].eql?("display")
          puts order[order.keys[0]]
        elsif order.keys[0].eql?("run")
          result = `#{order[order.keys[0]]}`
          puts result
          @socket.puts(result)
        end
      rescue
        puts "WHAT? Server is talking rubbish - \"#{order}\""
      end
    end
  end

  def client_name
    Socket.gethostname
  end

end

