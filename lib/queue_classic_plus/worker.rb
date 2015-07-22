module QueueClassicPlus
  class CustomWorker < QC::Worker
    BACKOFF_WIDTH = 10
    FailedQueue = QC::Queue.new("failed_jobs")

    def enqueue_failed(job, e)
      sql = "INSERT INTO #{QC::TABLE_NAME} (q_name, method, args, last_error) VALUES ('failed_jobs', $1, $2, $3)"
      last_error = e.backtrace ? ([e.message] + e.backtrace ).join("\n") : e.message
      QC.default_conn_adapter.execute sql, job[:method], JSON.dump(job[:args]), last_error

      QueueClassicPlus.exception_handler.call(e, job)
      Metrics.increment("qc.errors", source: @q_name)
    end

    def handle_failure(job, e)
      QueueClassicPlus.logger.info "Handling exception #{e.message} for job #{job[:id]}"
      klass = job_klass(job)

      # The mailers doesn't have a retries_on?
      if klass && klass.respond_to?(:retries_on?) && klass.retries_on?(e)
        remaining_retries = (job[:remaining_retries] || klass.max_retries).to_i
        remaining_retries -= 1

        if remaining_retries > 0
          klass.restart_in((klass.max_retries - remaining_retries) * BACKOFF_WIDTH,
                           remaining_retries,
                           *job[:args])
        else
          enqueue_failed(job, e)
        end
      else
        enqueue_failed(job, e)
      end

      FailedQueue.delete(job[:id])
    end

    private
    def job_klass(job)
      begin
        Object.const_get(job[:method].split('.')[0])
      rescue NameError
        nil
      end
    end
  end
end
