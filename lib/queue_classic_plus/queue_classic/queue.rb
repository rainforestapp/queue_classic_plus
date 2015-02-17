module QC
  class Queue
    def enqueue_retry_in(seconds, method, remaining_retries, *args)
      QC.log_yield(:measure => 'queue.enqueue') do
        s = "INSERT INTO #{TABLE_NAME} (q_name, method, args, scheduled_at, remaining_retries)
             VALUES ($1, $2, $3, now() + interval '#{seconds.to_i} seconds', $4)"
        res = conn_adapter.execute(s, name, method, JSON.dump(args), remaining_retries)
      end
    end
  end
end