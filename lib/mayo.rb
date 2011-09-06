module Mayo
  PORTS = {:connect => 2000, :response => 2001, :instruction => 2002}
  def self.command args                           #The Command line args which Mayo Accepts
    Mayo::Server.start if args.include?("server") #'mayo server'  - start a mayo server
    Mayo::Client.start(args[1]) if args.include?("connect")#'mayo connect' - start a client
    Mayo.socket_to(Socket.gethostname, Mayo::PORTS[:instruction]){|socket| socket.puts(args)  } if args.include?("run")  #'mayo run args'- sends intructions to active mayo server  
    Mayo.socket_to(Socket.gethostname, Mayo::PORTS[:instruction]){|socket| socket.puts("stop")} if args.include?("stop") #'mayo stop' - send server a shut down instruction  
  end

  def self.socket_to server, port, &blk   #helper method to perform some action with a socket
    socket = TCPSocket.open(server, port) #open socket
    yield(socket) #perform some logic with socket
    socket.close  #close the socket
  end
end

class Mayo::Job
  attr_reader :launcher, :ordnance
  attr_accessor :display

  def initialize launcher = "features", ordnance = nil, display = nil   
    m = {:features => "bundle exec cucumber -p all features/support/ features/step_definitions/", :specs => "bundle exec rspec"}
    @launcher = m[launcher.to_sym]  #select the full launch command if launcher matches either features or specs
    @launcher ||= launcher          #or use whatever is passed if not matched
    @ordnance = ordnance            #ordnance, the stuff to be fired with the launcher.  The Ordnance will be divied between the clients.
    @display = display              #An optional string which can be displayed when the Job is processed. 
  end

  def in_groups_of n = 1
    rand_tasks = @ordnance.sort_by{rand}#Randomize the tasks.  Reduce change of same test being run on same client.  Flushes out any inter-test interaction.
    j = 0 
    task_map = Array.new(rand_tasks.size){ j+=1; j=1 if j>n; j} #make array same size as tasks with stepped pattern [1,2,3,..,n,1,2,3,..,n etc]
    groups = rand_tasks.group_by{|t| task_map[rand_tasks.index(t)] }.values #group the tasks according to the above pattern     
    groups.map{|g| g.empty? ? nil : "#{@launcher} #{g.join(" ")}" } #map the group, prefixing the launcher command
  end
end

class Mayo::Server
  require 'socket'
  require 'json'
  require 'mayo/cuke_result_reader'
  require 'mayo/version'
  attr_accessor :clients
  
  def self.start   
    server = Mayo::Server.new
    server.open_ports               #starts 2 threaded processes; one to accept new client connections and the other to accept results
    server.listen_for_instructions  #main loop, wait for an instruction from user
  end
 
  def initialize
    puts "Initialising Mayo Server - preparing to spread"
    @project_dir = Dir.getwd   
    @clients, @threads, @results = Array.new(3){[]}
  end

  def open_ports
    @listen = true
    @threads = [ Thread.new { listen_for_clients },Thread.new { listen_for_response } ] #Create threads running TCPServers
  end

  def listen_for_clients  #maintain a TCP port to accept new client signups
    @client_server = TCPServer.open(Mayo::PORTS[:connect])
    server_data = {:project_dir => @project_dir, :servername => Socket.gethostname} #inf to send to clients on connect
    puts "Port #{Mayo::PORTS[:connect]} open to accept new clients. Client Command;\tmayo connect #{Socket.gethostname}"
    while @listen do
      Thread.start(@client_server.accept) do |client|                   #wait for a client to connect and start a new thread
        #TODO send the client the servers public key to be added to the clients authorized_keys
        client.puts(server_data.to_json)                                #Send data to client       
        client_data = JSON.parse(client.gets).merge!("socket" => client)#Add the socket to the client data
        @clients << client_data                                         #hold the client in Array
        puts ["Signing up client: #{client_data['name']}", client_data["mayo_version"] ? " - running version: #{client_data["mayo_version"]}" : ""].join
      end
    end
  end

  def listen_for_response   #maintain a TCP port to take data from active clients and display it.  This will change.  Better handling of returned data.
    @response_server = TCPServer.open(Mayo::PORTS[:response]) 
    while @listen do
      Thread.start(@response_server.accept) do |client|
        @results << read_while_client(client) #This could be improved! Multiple threads are sharing @results.  Replace with a memcached store and collect later?
        puts @results.last
        @jobs_left -= 1     
        show_results if @jobs_left == 0
      end
    end
  end

  def listen_for_instructions #maintain a TCP port to take intructions from Mayo.command
    puts "Port #{Mayo::PORTS[:instruction]} open for instructions"
    server = TCPServer.open(Mayo::PORTS[:instruction])
    while @listen do 
      #Thread.start(server.accept) do |client|
        client = server.accept
        orders = read_while_client(client)
        self.perform(orders) 
      #end    
    end
  end

  def read_while_client client, data = [] 
    while line = client.gets #read data from the client until the client disconects
      data << line.chop
    end
    data
  end

  def show_results
    puts @results.inspect
    puts "\n\n#{Array.new(80){'-'}.join}\n\tAll clients have retuned.  Time taken: #{Time.now - @jobs_started_at}seconds\n#{Array.new(80){'-'}.join}"
    cr = CukeResultReader.new(@results)
    begin
      cr.process_results
      cr.display_results(Time.now - @jobs_started_at)
      com = cr.failing_scenario_command
      if com
        puts "You can run just the failed tests again with the command 'mayo run last_failed'\nOr to run without mayo you can use this command;\n\n\t#{com.join(' ')}"
        @re_run_job = Mayo::Job.new(com[0], com[1].split(" "), "Re-runnnig tests which failed last time")
      end
    rescue
      puts "Unable to interpret results"
    end
    @results = []
  end

  def perform instruction
    puts "got order: #{instruction}"
    return self.stop if instruction.include?("stop") 
    job = self.make_job if instruction.eql?("run") #'mayo run' - no args
    job = self.make_job *instruction[1..instruction.size] if instruction.is_a?(Array) && instruction[0].eql?("run") #'mayo run features files' -with args
    return puts job if job.is_a?(String)  #when job is a string error message
    clients = current_clients             #get the current clients
    return puts("\e[31mNo Clients Connected\e[0m - Run 'mayo connect #{Socket.gethostname}' on client machines to connect clients") if clients.empty?
    update_active_clients        #send updated files to clients
    process_job(job)             #distribute the job amongst the clients
  end

  def make_job *args
    return @re_run_job || "\e[31mNo Recent failed results to run\e[0m - This command is available after running feature tests which have failures" if args.include?("last_failed")
    type = args[0] || "features"
    files_for = {"features" => "features/**/*.feature", "specs" => "spec/**/*spec.rb"}   
    args.delete_at(0) #remove the type arg.  
    files = args unless args.empty? #if array of files then no further action needed for files.
    files = get_files_from(*args.first.split(" ")) if args.size.eql?(1) #If array of 1, consider it to be a path PATTERN ie: features/**/*.feature  
    files ||= get_files_from(files_for[type]) #When no args present, use files_for hash with type for key to find the PATTERN
    files = features_by_scenario(files) if type.include?("features") || type.include?("cucumber") 
    Mayo::Job.new(type, files)
  end

  def process_job job, clients = current_clients
    @jobs_started_at = Time.now
    puts job.display  #Display job messgage if any
    jobs_for_clients = job.in_groups_of(clients.size).zip(clients) #assign the different clients thier part of the whole job
    @jobs_left = jobs_for_clients.select{|j,c| j}.size
    jobs_for_clients.each { |job, client| client["socket"].puts({:run_and_return => job}.to_json) unless job.nil? } #send instruction to client
  end

  def get_files_from(path);Dir[path];end

  def features_by_scenario files #given a set of feature files it will return an expanded set including the line numbers for each scenario.
    scenarios = files.map do |path|                 #For each features file ie: features/some.feature
      lines = File.open(path, 'r'){|f| f.readlines} #read the contents of the file
      selected = []
      before_feature_def = true                     #Set true to indicate that position is before first encounder of 'Feature'
      ignore_file = false                           #default is don't ignore the file
      last_line = ""                                #to remember the previous line
      lines.each_with_index do |line, index|        #For each line
        before_feature_def = false if line.match(/^Feature/) #change to false once passed first encouter of 'Feature'
        ignore_file = true if before_feature_def && line.include?("@wip") #if before 'Feature' and has '@wip' tag then ignore the whole file.
        selected << "#{path}:#{index+1}" if line.match(/Scenario/) && !(last_line.include?("@wip") || ignore_file) #consider a Scenario start line if line matches /Scenario/ and 
        #if @wip was not in the last_line or has ignore_file set to true.  If its a Scenario add the path plus lineNo. ie: features/some.feature:6
        last_line = line #remember previous line to help in above 
      end
      selected #return the selected lines as the output of the map.
    end
    scenarios.flatten
  end

  def update_active_clients clients = current_clients
    print "\nUpdating active clients with working directory"
    active_clients(clients) do |client|
      client["socket"].puts({:display => "receiving files"}.to_json)
      send_files_to_client client
      client["socket"].puts("goto_project_dir")
      client["socket"].puts({:run => "bundle install"}.to_json)
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

  def send_files_to_client client_data #RSYNC command to send files from server to client
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
  require 'mayo/version'

  def self.start server_name
    Dir.mkdir("mayo_testing") unless Dir.entries("./").include?("mayo_testing")
    Dir.chdir("mayo_testing")
    @root = Dir.getwd
    client = Mayo::Client.new
    client.register_with_server(server_name)
    client.wait_for_orders
  end    

  def initialize 
    @server_port = Mayo::PORTS[:connect]
    @client_data = {:username => Dir.getwd.split("/")[2], :name => Socket.gethostname, :working_dir => Dir.getwd, :mayo_version => Mayo::VERSION}
  end

  def register_with_server server_name
    @server = server_name
    @socket = TCPSocket.open(@server, @server_port) #Open a socket to the server
    @socket.puts(@client_data.to_json)              #Send server info
    @server_inf = JSON.parse(@socket.gets)          #Get info from server
    @project_name = @server_inf["project_dir"].split("/").last  #take the string after last / as project name
    @project_dir = Dir.getwd + "/" + @project_name  #project will be put in current dir/<project_name>
    puts "Registered with Mayo Server #{@server_inf["servername"]} for project #{@project_name}"
  end

  def wait_for_orders
    while order = @socket.gets    #wait until there is something to get from socket
      follow_orders order.chomp   #Send data read from socket to follow_orders
    end
  end

  def follow_orders order
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
      order = JSON.parse(order)
      action = order.keys[0]
      return puts order[action] if action.eql?("display")
      result = run_command(order[action]) if action.include?("run") #either run or run_and_return
      Mayo.socket_to(@server, Mayo::PORTS[:response]){|socket| socket.puts("Result from #{@client_data[:name]};\n\n#{result}\n\n") } if action.eql?("run_and_return")
    end
  end

  def run_command command
    result = `#{command}`
    puts "command complete"
    result
  end
end
