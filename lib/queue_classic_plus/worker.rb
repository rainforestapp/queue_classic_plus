require 'pg'
require 'queue_classic'

module QueueClassicPlus
  class CustomWorker < QC::Worker
    CONNECTION_ERRORS = [PG::UnableToSend, PG::ConnectionBad].freeze
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

      force_retry = false
      if connection_error?(e)
        # If we've got here, unfortunately ActiveRecord's rollback mechanism may
        # not have kicked in yet and we might be in a failed transaction. To be
        # *absolutely* sure the retry/failure gets enqueued, we do a rollback
        # just in case (and if we're not in a transaction it will be a no-op).
        QueueClassicPlus.logger.info "Reset connection for job #{job[:id]}"
        @conn_adapter.connection.reset
        @conn_adapter.execute 'ROLLBACK'

        # We definitely want to retry because the connection was lost mid-task.
        force_retry = true
      end
      klass = job_klass(job)

      if force_retry && !(klass.respond_to?(:disable_retries) && klass.disable_retries)
        klass_retries = klass.respond_to?(:max_retries) ? klass.max_retries : 0
        klass.restart_in(0, (job[:remaining_retries] || klass_retries || 0).to_i, *job[:args])
      # The mailers doesn't have a retries_on?
      elsif klass && klass.respond_to?(:retries_on?) && klass.retries_on?(e)
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

    def connection_error?(e)
      CONNECTION_ERRORS.any? { |klass| e.kind_of? klass } ||
        (e.respond_to?(:original_exception) &&
         CONNECTION_ERRORS.any? { |klass| e.original_exception.kind_of? klass })
    end
  end
end
