module Mayo
  def self.command args
    Mayo::Server.start if args.include?("server")
    Mayo::Server.run(args)   if args.include?("run")
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
    server.open_ports
    server.listen_for_intructions #listen for instrunctions sent via memcached 
  end

  def self.run args = nil
    @cache = Dalli::Client.new('localhost:11211')   
    @cache.set("mayo_instruction", "run")
  end

  def self.stop
    @cache = Dalli::Client.new('localhost:11211')   
    @cache.set("mayo_instruction", "stop")
  end

  attr_accessor :clients, :listen

  def initialize
    puts "Initializing Mayo Server - The Rich Creamy Goodness of your tests will soon be spread."
    @port = {:client_connect => 2000, :client_response => 2001}
    @cache = Dalli::Client.new('localhost:11211')   
    @project_dir = Dir.getwd   
    @clients = []
  end

  def open_ports
    @listen = true
    @threads = [ 
      Thread.new { listen_for_clients }, #Create a thread which accepts connections from new clients
      Thread.new { listen_for_response } #Create a thread which takes and displays info from clients
    ]
  end

  def listen_for_clients
    server = TCPServer.open(@port[:client_connect])
    puts "Port #{@port[:client_connect]} open to accept new clients"

    while @listen do
      client = server.accept
      #TODO send the client the servers public key to be added to the clients authorized_keys
      client.puts({:project_dir => @project_dir, :servername => Socket.gethostname}.to_json) #Send data to client       
      client_data = client.gets # Read info from client       
      client_data = JSON.parse(client_data).merge!("socket" => client)
      @clients << client_data
      puts "Signing up client: #{client_data['name']}"       
    end
  end

  def listen_for_response
    server = TCPServer.open(2001)
    while @listen do
      client = server.accept
      while data = client.gets
        puts data
      end
      @jobs_left -= 1
      if @jobs_left == 0
        t = Time.now
        puts "WOOOO jobs done"
        puts (t - @jobs_started_at)
      end
    end
  end

  def listen_for_instructions
    @cache.set("mayo_instruction", nil) #make sure no old instruction
    puts "waiting for orders"     
    while @cache.get("mayo_instruction").nil?
    end
    self.perform(@cache.get("mayo_instruction"))
    @cache.set("mayo_instruction", nil)     #reset cache
  end

  def perform instruction
    puts "got order: #{instruction}"
    case instruction
    when "run"
      run_tests
    when "stop"
      return self.stop
    end
    listen_for_instructions
  end

  def run_tests
    update_active_clients
    tasks = {
      :features => {:files => detailed_cuke_files(Dir['features/**/*.feature']), :command_prefix => "bundle exec cucumber -p all features/support/ features/step_definitions/"},
      :specs => {:files => Dir['spec/**/*spec.rb'], :command_prefix => "bundle exec rspec"}
    }
    task = tasks[:features]

    jobs = divide_tasks task[:files]
    @jobs_left = jobs.size
    @jobs_started_at = Time.now
    active_clients do |client, index|
      command = "#{task[:command_prefix]} #{jobs[index].join(" ")}"
      client["socket"].puts({:run_and_return => command}.to_json)
    end
    
  end

  def detailed_cuke_files files = Dir['features/**/*.feature']
    scenarios = files.map do |path|
      lines = File.open(path, 'r'){|f| f.readlines}
      selected = []
      lines.each_with_index do |line, index|
        selected << "#{path}:#{index+1}" if line.match(/Scenario/)
      end
      selected
    end
    scenarios.flatten
  end

  def divide_tasks tasks
    rand_tasks = tasks.sort_by{rand} 
    groups = Array.new(current_clients.size){[]}
    i = 0
    until rand_tasks.empty?
      groups[i].push(rand_tasks.pop)
      i+=1
      i = 0 if i > (groups.size - 1)
    end
    groups
  end

  def update_active_clients
    clients = current_clients
    print "\nUpdating Active Clients' Data"
    active_clients(clients) do |client|
      print(".")
      client["socket"].puts({:display => "receiving files"}.to_json)
      send_files_to_client client
      client["socket"].puts("goto_project_dir")
      client["socket"].puts({:run => "bundle install"}.to_json)
    end
    puts "\tUpdated #{clients.size} clients"
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

  def active_clients clients = current_clients, &blk
    clients.each_with_index do |client, index|
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
    Dir.mkdir("mayo_testing") unless Dir.entries("./").include?("mayo_testing")
    Dir.chdir("mayo_testing")   
    client = Mayo::Client.new
    client.register_with_server
    client.wait_for_orders
  end    

  def initialize
    @server = 'yokai'
    @server_port = 2000
    username = Dir.getwd.split("/")[2]
    @client_data = {:username => username, :name => client_name, :working_dir => Dir.getwd}
  end

  def register_with_server
    @socket = TCPSocket.open(@server, @server_port) #Open a socket to the server
    @socket.puts(@client_data.to_json)              #Send server info
    @server_inf = JSON.parse(@socket.gets)          #Get info from server

    @project_name = @server_inf["project_dir"].split("/").last  #take the string after last / as project name
    @project_dir = Dir.getwd + "/" + @project_name  #project will be put in current dir/<project_name>
    puts "Registered with Mayo Server #{@server_inf["servername"]} for project #{@project_name}"
  end

  def wait_for_orders
    order = true
    while !order.nil?
      print "."
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
    when "goto_project_dir"
      Dir.chdir(@project_dir)
      puts "now in #{Dir.getwd}"
    else
      begin
        order = JSON.parse(order)
      rescue
        puts "WHAT? Server is talking rubbish - \"#{order}\""
      end
      action = order.keys[0]
      if action.eql?("display")
        puts order[action]
      elsif action.eql?("run")
        puts run_command(order[action])
      elsif action.eql?("run_and_return")
        result = run_command(order[action])
        result_socket = TCPSocket.open(@server, @server_port + 1)
        result_socket.puts(result)
        result_socket.close
      end
    end
  end

  def run_command command
    result = `#{command}`
    puts "command complete"
    result
  end

  def client_name
    Socket.gethostname
  end

end

