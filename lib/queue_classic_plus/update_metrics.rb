module QueueClassicPlus
  module UpdateMetrics
    def self.update
      metrics.each do |name, values|
        if values.respond_to?(:each)
          values.each do |hash|
            hash.to_a.each do |(source, count)|
              Metrics.measure("qc.#{name}", count, source: source)
            end
          end
        else
          Metrics.measure("qc.#{name}", values)
        end
      end
    end

    def self.metrics
      {
        jobs_queued: jobs_queued,
        jobs_scheduled: jobs_scheduled,
        max_created_at: max_age("created_at"),
        max_locked_at: max_age("locked_at"),
        "max_created_at.unlocked" => max_age("locked_at", "locked_at IS NULL"),
        "jobs_delayed.lag" => lag,
        "jobs_delayed.late_count" => late_count,
      }
    end

    def self.jobs_queued
      sql_group_count "SELECT q_name AS group, COUNT(1)
              FROM queue_classic_jobs
              WHERE scheduled_at <= NOW() GROUP BY q_name"
    end

    def self.jobs_scheduled
      sql_group_count "SELECT q_name AS group, COUNT(1)
              FROM queue_classic_jobs
              WHERE scheduled_at > NOW() GROUP BY q_name"
    end

    def self.lag
      lag = execute("SELECT MAX(EXTRACT(EPOCH FROM now() - scheduled_at)) AS lag
              FROM queue_classic_jobs
              WHERE scheduled_at <= NOW()").first
      lag ? lag['lag'].to_f : 0.0
    end

    def self.late_count
      nb_late = execute("SELECT COUNT(1)
         FROM queue_classic_jobs
         WHERE scheduled_at < NOW()").first
      nb_late ? Integer(nb_late['count']) : 0
    end

    private

    def self.sql_group_count(sql)
      results = execute(sql)
      results.map do |h|
        {
          h.fetch("group") => Integer(h.fetch('count'))
        }
      end
    end

    def self.max_age(column, *conditions)
      conditions.unshift "q_name != '#{::QueueClassicPlus::CustomWorker::FailedQueue.name}'"
      conditions.unshift "scheduled_at <= NOW()"

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
