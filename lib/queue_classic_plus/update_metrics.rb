module QueueClassicPlus
  module UpdateMetrics
    def self.update
      {
        "queued" => "queue_classic_jobs",
        "scheduled" => "queue_classic_later_jobs",
      }.each do |type, table|
        next unless ActiveRecord::Base.connection.table_exists?(table)
        q = "SELECT q_name, COUNT(1) FROM #{table} GROUP BY q_name"
        results = execute(q)

        # Log individual queue sizes
        results.each do |h|
          Metrics.measure("qc.jobs_#{type}", h.fetch('count').to_i, source: h.fetch('q_name'))
        end
      end

      # Log oldest locked_at and created_at
      ['locked_at', 'created_at'].each do |column|
        age = max_age(column)
        Metrics.measure("qc.max_#{column}", age)
      end

      # Log oldes unlocked jobs
      age = max_age("created_at", "locked_at IS NULL")
      Metrics.measure("qc.max_created_at.unlocked", age)

      if ActiveRecord::Base.connection.table_exists?('queue_classic_later_jobs')
        lag = execute("SELECT MAX(EXTRACT(EPOCH FROM now() - not_before)) AS lag 
                FROM queue_classic_later_jobs").first
                lag = lag ? lag['lag'] : 0

        Metrics.measure("qc.jobs_delayed.lag", lag.to_f)

        nb_late = execute("SELECT COUNT(1) 
           FROM queue_classic_later_jobs 
           WHERE not_before < NOW()").first
        nb_late = nb_late ? nb_late['count'] : 0

        Metrics.measure("qc.jobs_delayed.late_count", nb_late.to_i)
      end
    end

    private
    def self.max_age(column, *conditions)
      conditions.unshift "q_name != '#{::QueueClassicPlus::CustomWorker::FailedQueue.name}'"

      q = "SELECT EXTRACT(EPOCH FROM now() - #{column}) AS age_in_seconds 
           FROM queue_classic_jobs
           WHERE #{conditions.join(" AND ")}
           ORDER BY age_in_seconds DESC
           "
       age_info = execute(q).first

       age_info ? age_info['age_in_seconds'].to_i : 0
    end

    def self.execute(q)
      ActiveRecord::Base.connection.execute(q)
    end
  end
end
