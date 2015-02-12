module QueueClassicPlus
  module UpdateMetrics
    def self.update
      [
        "queued",
        "scheduled",
      ].each do |type|
        q = case type
            when "queued"
              "SELECT q_name, COUNT(1)
              FROM queue_classic_jobs
              WHERE scheduled_at IS NULL GROUP BY q_name"
            when "scheduled"
              "SELECT q_name, COUNT(1)
              FROM queue_classic_jobs
              WHERE scheduled_at IS NOT NULL GROUP BY q_name"
            else
              raise "Unknown type #{type}"
            end

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

      # Log oldest unlocked jobs
      age = max_age("created_at", "locked_at IS NULL")
      Metrics.measure("qc.max_created_at.unlocked", age)

      lag = execute("SELECT MAX(EXTRACT(EPOCH FROM now() - scheduled_at)) AS lag
              FROM queue_classic_jobs").first
              lag = lag ? lag['lag'] : 0

      Metrics.measure("qc.jobs_delayed.lag", lag.to_f)

      nb_late = execute("SELECT COUNT(1)
         FROM queue_classic_jobs
         WHERE scheduled_at < NOW()").first
      nb_late = nb_late ? nb_late['count'] : 0

      Metrics.measure("qc.jobs_delayed.late_count", nb_late.to_i)
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
