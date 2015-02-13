namespace :qc_plus do
  desc "Start a new worker for the (default or $QUEUE) queue"
  task :work  => :environment do
    parallel = false
    worker_count = Integer(ENV.fetch("QC_WORKER_COUNT", 1))

    begin
      require 'parallel'
      parallel = true
    rescue LoadError
    end

    if !parallel && worker_count != 1
      $stderr.puts("You must install the parallel gem to sue multiple workers.")
      exit 1
    end


    def setup_signal(worker)
      trap('INT') do
        $stderr.puts("Received INT. Shutting down.")
        workers.each(&:stop)
      end

      trap('TERM') do
        $stderr.puts("Received Term. Shutting down.")
        workers.each(&:stop)
      end
    end

    if parallel
      begin
        Parallel.each(1..worker_count) do |worker|
          worker = QueueClassicPlus::CustomWorker.new
          puts "Starting QC worker #{Process.pid}"
          setup_signal worker
          worker.start
        end
      rescue Interrupt
      end
    else
      worker = QueueClassicPlus::CustomWorker.new
      setup_signal worker
      puts "Starting QC worker"
      worker.each(&:start)
    end
  end
end
