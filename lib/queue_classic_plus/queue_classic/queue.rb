module QC
  class Queue

    def enqueue_retry_in(seconds, method, remaining_retries, *args)
      QC.log_yield(:measure => 'queue.enqueue') do
        s = "INSERT INTO #{QC.table_name} (q_name, method, args, scheduled_at, remaining_retries)
             VALUES ($1, $2, $3, now() + interval '#{seconds.to_i} seconds', $4)
             RETURNING *"

        conn_adapter.execute(s, name, method, JSON.dump(args), remaining_retries)
      end
    end

    def lock
      QC.log_yield(:measure => 'queue.lock') do
        s = <<~SQL
          WITH selected_job AS (
            SELECT id
            FROM queue_classic_jobs
            WHERE
              locked_at IS NULL AND
              q_name = $1 AND
              scheduled_at <= now()
            LIMIT 1
            FOR NO KEY UPDATE SKIP LOCKED
          )
          UPDATE queue_classic_jobs
          SET
            locked_at = now(),
            locked_by = pg_backend_pid()
          FROM selected_job
          WHERE queue_classic_jobs.id = selected_job.id
          RETURNING *
        SQL

        if r = conn_adapter.execute(s, name)
          {}.tap do |job|
            job[:id] = r["id"]
            job[:q_name] = r["q_name"]
            job[:method] = r["method"]
            job[:args] = JSON.parse(r["args"])
            job[:remaining_retries] = r["remaining_retries"]&.to_s
            if r["scheduled_at"]
              # ActiveSupport may cast time strings to Time
              job[:scheduled_at] = r["scheduled_at"].kind_of?(Time) ? r["scheduled_at"] : Time.parse(r["scheduled_at"])
              ttl = Integer((Time.now - job[:scheduled_at]) * 1000)
              QC.measure("time-to-lock=#{ttl}ms source=#{name}")
            end
          end
        end
      end
    end

  end
end
