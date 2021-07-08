namespace :qc_plus do
  desc "Start a new worker for the (default or $QUEUE) queue"
  task :work  => :environment do
    puts "Starting up worker for queue #{ENV['QUEUE']}"

    # ActiveRecord::RecordNotFound is ignored by Sentry by default,
    # which shouldn't happen in background jobs.
    if defined?(Sentry)
      Sentry.init do |config|
        config.excluded_exceptions = []
        config.background_worker_threads = 0 if Gem::Version.new(Sentry::VERSION) >= Gem::Version.new('4.1.0')
      end
    elsif defined?(Raven)
      Raven.configure do |config|
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
