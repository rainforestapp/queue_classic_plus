namespace :qc_plus do
  desc "Start a single worker"
  task :work_one => :environment do
    worker = QueueClassicPlus::CustomWorker.new
    puts "Starting QC worker #{Process.pid}"
    worker.start

    trap('INT') do
      $stderr.puts("Received INT. Shutting down.")
      workers.each(&:stop)
    end

    trap('TERM') do
      $stderr.puts("Received Term. Shutting down.")
      workers.each(&:stop)
    end
  end

  desc "Start one or many new workers for the (default or $QUEUE) queue"
  task :work do
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

    if parallel
      begin
        Parallel.each(1..worker_count) do |worker|
          Rake::Task["environment"].execute
          Rake::Task["qc_plus:work_one"].execute
        end
      rescue Interrupt
      end
    else
      Rake::Task["environment"].execute
      Rake::Task["work_one"].execute
    end
  end
end
