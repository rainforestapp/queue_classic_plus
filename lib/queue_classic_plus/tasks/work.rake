namespace :qc_plus do
  desc "Start a new worker for the (default or $QUEUE) queue"
  task :work  => :environment do
    puts "Starting up worker for queue #{ENV['QUEUE']}"
    @worker = QueueClassicPlus::CustomWorker.new

    trap('INT') do
      $stderr.puts("Received INT. Shutting down.")
      if !@worker.running
        $stderr.puts("Worker has stopped running. Exit.")
        exit(1)
      end
      @worker.stop
      exit
    end

    trap('TERM') do
      $stderr.puts("Received Term. Shutting down.")
      @worker.stop
      exit
    end

    @worker.start
  end
end
