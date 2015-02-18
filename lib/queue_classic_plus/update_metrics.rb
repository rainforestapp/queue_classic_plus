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
        max_locked_at: max_age("locked_at", "locked_at IS NOT NULL"),
        "max_created_at.unlocked" => max_age("locked_at", "locked_at IS NULL"),
        "jobs_delayed.lag" => max_age("scheduled_at"),
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

    def self.late_count
      nb_late = execute("SELECT COUNT(1)
         FROM queue_classic_jobs
         WHERE scheduled_at < NOW() AND #{not_failed}")
      nb_late ? Integer(nb_late['count']) : 0
    end

    private

    def self.sql_group_count(sql)
      results = execute(sql)
      results = [results] if Hash === results
      Array(results).map do |h|
        {
          h.fetch("group") => Integer(h.fetch('count'))
        }
      end
    end

    def self.max_age(column, *conditions)
      conditions.unshift not_failed
      conditions.unshift "scheduled_at <= NOW()"

      # This is to support `jobs_delayed.lag`. Basically, comparing the same column
      # with itself to know max_age isn't helpful.
      reference_time = column.to_s == 'created_at' ? 'scheduled_at' : 'now()'

      q = "SELECT EXTRACT(EPOCH FROM #{reference_time} - #{column}) AS age_in_seconds
           FROM queue_classic_jobs
           WHERE #{conditions.join(" AND ")}
           ORDER BY age_in_seconds DESC
           LIMIT 1
           "
       age_info = execute(q)

       age_info ? age_info['age_in_seconds'].to_i : 0
    end

    def self.execute(q)
      QC.default_conn_adapter.execute(q)
    end

    def self.not_failed
      "q_name != '#{::QueueClassicPlus::CustomWorker::FailedQueue.name}'"
    end
  end
end
