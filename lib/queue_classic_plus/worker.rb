module QueueClassicPlus
  class CustomWorker < QC::Worker
    class QueueClassicJob < ActiveRecord::Base
    end

    BACKOFF_WIDTH = 10
    FailedQueue = QC::Queue.new("failed_jobs")

    def enqueue_failed(job, e)
      ActiveRecord::Base.transaction do
        FailedQueue.enqueue(job[:method], *job[:args])
        new_job = QueueClassicAdmin::QueueClassicJob.order(:id).where(q_name: 'failed_jobs').last
        new_job.last_error = if e.backtrace then ([e.message] + e.backtrace ).join("\n") else e.message end
        new_job.save!
      end

      QueueClassicPlus.exception_handler.call(e, job)
      Metrics.increment("qc.errors", source: @q_name)
    end

    def handle_failure(job, e)
      Rails.logger.info "Handling exception #{e.message} for job #{job[:id]}"
      klass = job_klass(job)

      model = QueueClassicJob.find(job[:id])

      # The mailers doesn't have a retries_on?
      if klass && klass.respond_to?(:retries_on?) && klass.retries_on?(e)
        remaining_retries = model.remaining_retries || klass.max_retries
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
      model.destroy
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
