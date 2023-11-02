require 'pg'
require 'queue_classic'

module QueueClassicPlus
  class CustomWorker < QC::Worker
    CONNECTION_ERRORS = [PG::UnableToSend, PG::ConnectionBad].freeze
    BACKOFF_WIDTH = 10
    FailedQueue = QC::Queue.new("failed_jobs")

    def handle_failure(job, e)
      QueueClassicPlus.logger.info "Handling exception #{e.class} - #{e.message} for job #{job[:id]}"

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

      @failed_job = job
      @raw_args = job[:args]
      @failed_job_args = failed_job_class ? failed_job_class.deserialized(@raw_args) : @raw_args

      if force_retry && !(failed_job_class.respond_to?(:disable_retries) && failed_job_class.disable_retries)
        Metrics.increment("qc.force_retry", source: @q_name)
        retry_with_remaining(e)
      # The mailers doesn't have a retries_on?
      elsif failed_job_class.respond_to?(:retries_on?) && failed_job_class.retries_on?(e)
        Metrics.increment("qc.retry", source: @q_name)
        retry_with_remaining(e)
      else
        enqueue_failed(e)
      end

      FailedQueue.delete(@failed_job[:id])
    end

    private

    def retry_with_remaining(e)
      if remaining_retries > 0
        failed_job_class.restart_in(backoff, remaining_retries - 1, *@failed_job_args)
      else
        enqueue_failed(e)
      end
    end

    def max_retries
      failed_job_class.respond_to?(:max_retries) ? failed_job_class.max_retries : 5
    end

    def remaining_retries
      (@failed_job[:remaining_retries] || max_retries).to_i
    end

    def failed_job_class
      return @failed_job_class if @failed_job_class_memoized

      @failed_job_class_memoized = true
      @failed_job_class =
      begin
        Object.const_get(@failed_job[:method].split('.')[0])
      rescue NameError
        nil
      end
    end

    def backoff
      (max_retries - (remaining_retries - 1)) * BACKOFF_WIDTH
    end

    def connection_error?(e)
      CONNECTION_ERRORS.any? { |klass| e.kind_of? klass } ||
        (e.respond_to?(:original_exception) &&
         CONNECTION_ERRORS.any? { |klass| e.original_exception.kind_of? klass })
    end

    def enqueue_failed(e)
      sql = "INSERT INTO #{QC.table_name} (q_name, method, args, last_error) VALUES ('failed_jobs', $1, $2, $3)"
      last_error = e.backtrace ? ([e.message] + e.backtrace ).join("\n") : e.message

      QC.default_conn_adapter.execute sql, @failed_job[:method], JSON.dump(@raw_args), last_error

      QueueClassicPlus.exception_handler.call(e, @failed_job)
      Metrics.increment("qc.errors", source: @q_name)
    end
  end
end
