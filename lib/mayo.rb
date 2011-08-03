module Mayo
  def self.command args
    Mayo::Server.start if args.include?("server")
    Mayo::Server.run(args) if args.include?("run")
    Mayo::Server.stop   if args.include?("stop")   
    Mayo::Client.start if args.include?("connect")
  end
end

class Mayo::Server
  require 'socket'
  require 'json'

  def self.start   
    server = Mayo::Server.new
    server.open_ports
    server.listen_for_instructions #listen for instrunctions sent via memcached 
  end

  def self.run args = nil
    socket = TCPSocket.open(Socket.gethostname, 2002)
    socket.puts(args)
    socket.close
  end

  def self.stop
    socket = TCPSocket.open(Socket.gethostname, 2002)
    socket.puts("stop")
    socket.close    
  end

  attr_accessor :clients, :listen

  def initialize
    puts "Initializing Mayo Server - The Rich Creamy Goodness of your tests will soon be spread."
    @port = {:client_connect => 2000, :client_response => 2001, :server_instruct => 2002} 
    @project_dir = Dir.getwd   
    @clients = []
    @threads = []
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
    server = TCPServer.open(@port[:client_response])
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
    puts "Port #{@port[:server_instruct]} open for instructions"
    server = TCPServer.open(@port[:server_instruct])
    while @listen
      c = server.accept
      orders = []
      while order = c.gets
        orders << order.chop
      end
      self.perform(orders) 
    end
  end

  def perform instruction
    puts "got order: #{instruction}"
    return self.stop if instruction.eql?("stop")
    return self.run_tests if instruction.eql?("run")

    if instruction.is_a?(Array)
      if instruction[0].eql?("run")
        self.run_tests instruction[1..instruction.size]
      end
    end

  end

  def run_tests *args
    args.flatten!
    return puts("No Clients") if current_clients.empty?
    update_active_clients

    files_for = {"features" => "features/**/*.feature", "specs" => "spec/**/*spec.rb"}
    prefi = {"features" => "bundle exec cucumber -p all features/support/ features/step_definitions/", "specs" => "bundle exec rspec"}
    type = args[0] || "features"
    files = get_files_from(args[1]) if args[1]
    files ||= get_files_from(files_for[type])
    prefix = prefi[type]

    jobs = divide_tasks files
    @jobs_left = jobs.size
    @jobs_started_at = Time.now
    active_clients do |client, index|
      command = "#{prefix} #{jobs[index].join(" ")}"
      client["socket"].puts({:run_and_return => command}.to_json)
    end    
  end

  def get_files_from path
    Dir[path]
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
    @listen = false
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

