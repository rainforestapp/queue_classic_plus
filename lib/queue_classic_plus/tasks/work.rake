namespace :qc_plus do
  desc "Start a new worker for the (default or $QUEUE) queue"
  task :work  => :environment do
    puts "Starting up worker for queue #{ENV['QUEUE']}"

    if defined? Raven
      Raven.configure do |config|
        # ActiveRecord::RecordNotFound is ignored by Raven by default,
        # which shouldn't happen in background jobs.
        config.excluded_exceptions = []
      end
    end

    @worker = QueueClassicPlus::CustomWorker.new

    trap('INT') do
      $stderr.puts("Received INT. Shutting down.")
      if !@worker.running
        $stderr.puts("Worker has already stopped running.")
      end
      @worker.stop
    end

    trap('TERM') do
      $stderr.puts("Received Term. Shutting down.")
      @worker.stop
    end

    @worker.start
    $stderr.puts 'Shut down successfully'
  end
end
