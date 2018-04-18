module QC
  class Queue

    def enqueue_retry_in(seconds, method, remaining_retries, *args)
      QC.log_yield(:measure => 'queue.enqueue') do
        s = "INSERT INTO #{TABLE_NAME} (q_name, method, args, scheduled_at, remaining_retries)
             VALUES ($1, $2, $3, now() + interval '#{seconds.to_i} seconds', $4)"

        conn_adapter.execute(s, name, method, JSON.dump(args), remaining_retries)
      end
    end

    def lock
      QC.log_yield(:measure => 'queue.lock') do
        s = "SELECT * FROM lock_head($1, $2)"
        if r = conn_adapter.execute(s, name, top_bound)
          {}.tap do |job|
            job[:id] = r["id"]
            job[:q_name] = r["q_name"]
            job[:method] = r["method"]
            job[:args] = JSON.parse(r["args"])
            job[:remaining_retries] = r["remaining_retries"]
            if r["scheduled_at"]
              job[:scheduled_at] = Time.parse(r["scheduled_at"])
              ttl = Integer((Time.now - job[:scheduled_at]) * 1000)
              QC.measure("time-to-lock=#{ttl}ms source=#{name}")
            end
          end
        end
      end
    end

  end
end
