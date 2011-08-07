module Mayo
  PORTS = {:connect => 2000, :response => 2001, :instruction => 2002}

  def self.command args                           #The Command line args which Mayo Accepts
    Mayo::Server.start if args.include?("server") #'mayo server'  - start a mayo server
    Mayo::Client.start if args.include?("connect")#'mayo connect' - start a client
    Mayo::Server.run(args) if args.include?("run")#'mayo run args'- sends intructions to active mayo server  
    Mayo::Server.stop   if args.include?("stop")  #'mayo stop'    - send server a shut down intruction  
  end

  def self.socket_to server, port, &blk   #helper method to perform some action with a socket
    socket = TCPSocket.open(server, port) #open socket
    yield(socket) #perform some logic with socket
    socket.close  #close the socket
  end
end

class Mayo::Server
  require 'socket'
  require 'json'
  require 'mayo/cuke_result_reader'

  def self.start   
    server = Mayo::Server.new
    server.open_ports #starts 2 threaded processes; one to accept new client connections and the other to accept results
    server.listen_for_instructions #main loop, wait for an instruction 
  end
  def self.run *args
    args = "run" if args.empty?
    Mayo.socket_to(Socket.gethostname, Mayo::PORTS[:instruction]){|socket| socket.puts(args) }
  end
  def self.stop
    Mayo.socket_to(Socket.gethostname, Mayo::PORTS[:instruction]){|socket| socket.puts("stop") }
  end

  def initialize
    puts "Initializing Mayo Server - The Rich Creamy Goodness of your tests will soon be spread."
    @project_dir = Dir.getwd   
    @clients = []
    @threads = []
  end

  def open_ports
    @listen = true
    @threads = [ 
      Thread.new { listen_for_clients }#, #Create a thread which accepts connections from new clients
      #Thread.new { listen_for_response } #Create a thread which takes and displays info from clients
    ]
  end

  def listen_for_clients  #maintain a TCP port to accept new client signups
    server = TCPServer.open(Mayo::PORTS[:connect])
    server_data = {:project_dir => @project_dir, :servername => Socket.gethostname} #inf to send to clients on connect
    puts "Port #{Mayo::PORTS[:connect]} open to accept new clients"
    while @listen do
      client = server.accept                                            #wait for a client to connect
      #TODO send the client the servers public key to be added to the clients authorized_keys
      client.puts(server_data.to_json)                                  #Send data to client       
      client_data = client.gets                                         #Read info from client       
      client_data = JSON.parse(client_data).merge!("socket" => client)  #Add the socket to the client data
      @clients << client_data                                           #hold the client in Array
      puts "Signing up client: #{client_data['name']}"
    end
  end

  def listen_for_response   #maintain a TCP port to take data from active clients and display it.  This will change.  Better handling of returned data.
    
    server = TCPServer.open(Mayo::PORTS[:response]) 
    @results ||= []
    while @listen do
      @results << read_while_client(server.accept)
      puts @results.last
      @jobs_left -= 1
      if @jobs_left == 0

        
        puts @results.inspect
        puts "\n\n----------------------------------------------------------------------------------"
        puts "   All clients have retuned.  Time taken: #{Time.now - @jobs_started_at}seconds"     
        puts "----------------------------------------------------------------------------------\n\n"
        cr = CukeResultReader.new(@results)
        cr.process_results
        cr.display_results
        
        @listen = false
        
      end
    end
    server.close
  end

  def listen_for_instructions #maintain a TCP port to take intructions from Mayo.command
    puts "Port #{Mayo::PORTS[:instruction]} open for instructions"
    server = TCPServer.open(Mayo::PORTS[:instruction])
    while @listen
      orders = read_while_client(server.accept)
      self.perform(orders) 
    end
  end

  def read_while_client client, data = [] 
    while line = client.gets #read data from the client until the client disconects
      data << line.chop
    end
    data
  end

  def perform instruction
    puts "got order: #{instruction}"
    return self.stop if instruction.include?("stop") 
    return self.run_tests if instruction.eql?("run")  
    self.run_tests *instruction[1..instruction.size] if instruction.is_a?(Array) && instruction[0].eql?("run")
  end

  def run_tests *args
    return puts("No Clients") if current_clients.empty?
    update_active_clients

    files_for = {"features" => "features/**/*.feature", "specs" => "spec/**/*spec.rb"}
    prefix = {"features" => "bundle exec cucumber -p all features/support/ features/step_definitions/", "specs" => "bundle exec rspec"}

    type = args[0] || "features"
    files = get_files_from(*args[1].split(" ")) if args[1]
    files ||= get_files_from(files_for[type])
    prefix = prefix[type] || type
    files = features_by_scenario(files) if prefix.include?("cucumber")

    jobs = divide_tasks files
    @jobs_left = jobs.size
    @jobs_started_at = Time.now
    active_clients do |client, index|
      command = "#{prefix} #{jobs[index].join(" ")}"
      client["socket"].puts({:run_and_return => command}.to_json)
    end    
    listen_for_response
  end

  def get_files_from(path);Dir[path];end

  def features_by_scenario files
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
      client["socket"].puts({:display => "receiving files"}.to_json)
      send_files_to_client client
      client["socket"].puts("goto_project_dir")
      client["socket"].puts({:run => "bundle install"}.to_json)
      #client["socket"].puts({:run => "bundle exec rake db:migrate && bundle exec rake db:test:prepare"}.to_json)
      print(".")
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
    `rsync -avc -e ssh --delete --ignore-errors --exclude='*.log' #{@project_dir} #{client_data["username"]}@#{client_data["name"]}:#{client_data["working_dir"]}`
  end

  def active_clients clients = current_clients, &blk
    clients.each_with_index{ |client, index| yield(client, index) }
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
    @root = Dir.getwd
    client = Mayo::Client.new
    client.register_with_server
    client.wait_for_orders
  end    

  def initialize
    @server = 'yokai'
    @server_port = Mayo::PORTS[:connect]
    @client_data = {:username => Dir.getwd.split("/")[2], :name => client_name, :working_dir => Dir.getwd}
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
    when "reset"
      Dir.chdir(@root)
      FileUtils.rm_rf(@project_dir)
    else
      begin
        order = JSON.parse(order)
      rescue
        puts "WHAT? Server is talking rubbish - \"#{order}\""
      end
      action = order.keys[0]
      return puts order[action] if action.eql?("display")
      result = run_command(order[action]) if action.include?("run") #either run or run_and_return
      Mayo.socket_to(@server, Mayo::PORTS[:response]){|socket| socket.puts("Result from #{@client_data[:name]}\n#{result}") } if action.eql?("run_and_return")
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

