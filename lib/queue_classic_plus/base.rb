module QueueClassicPlus
  class Base
    def self.queue
      QC::Queue.new(@queue)
    end

    class_attribute :locked
    class_attribute :skip_transaction
    class_attribute :retries_on
    class_attribute :max_retries

    self.max_retries = 0
    self.retries_on = {}

    def self.retry!(on: RuntimeError, max: 5)
      Array(on).each {|e| self.retries_on[e] = true}
      self.max_retries = max
    end

    def self.retries_on? exception
      self.retries_on[exception.class] || self.retries_on.keys.any? {|klass| exception.is_a? klass}
    end

    def self.lock!
      self.locked = true
    end

    def self.skip_transaction!
      self.skip_transaction = true
    end

    def self.locked?
      !!self.locked
    end

    def self.logger
      QueueClassicPlus.logger
    end

    def self.can_enqueue?(method, *args)
      if locked?
        max_lock_time = ENV.fetch("QUEUE_CLASSIC_MAX_LOCK_TIME", 10 * 60).to_i

        q = "SELECT COUNT(1) AS count
             FROM
               (
                 SELECT 1
                 FROM queue_classic_jobs
                 WHERE q_name = $1 AND method = $2 AND args::text = $3::text
                   AND (locked_at IS NULL OR locked_at > current_timestamp - interval '#{max_lock_time} seconds')
               )
             as x"

        result = QC.default_conn_adapter.execute(q, @queue, method, args.to_json)
        result['count'].to_i == 0
      else
        true
      end
    end

    def self.enqueue(method, *args)
      if can_enqueue?(method, *args)
        queue.enqueue(method, *args)
      end
    end

    def self.enqueue_perform(*args)
      enqueue("#{self.to_s}._perform", *args)
    end

    def self.enqueue_perform_in(time, *args)
      raise "Can't enqueue in the future for locked jobs" if locked?
      queue.enqueue_in(time, "#{self.to_s}._perform", *args)
    end

    def self.restart_in(time, remaining_retries, *args)
      queue.enqueue_retry_in(time, "#{self.to_s}._perform", remaining_retries, *args)
    end

    def self.do(*args)
      Metrics.timing("qc_enqueue_time", source: librato_key) do
        enqueue_perform(*args)
      end
    end

    def self._perform(*args)
      Metrics.timing("qu_perform_time", source: librato_key) do
        if skip_transaction
          perform *args
        else
          transaction do
            perform *args
          end
        end
      end
    end

    def self.librato_key
      (self.name || "").underscore.gsub(/\//, ".")
    end

    def self.transaction(options = {}, &block)
      ActiveRecord::Base.transaction(options, &block)
    end

    # Debugging
    def self.list
      q = "SELECT * FROM queue_classic_jobs WHERE q_name = '#{@queue}'"
      ActiveRecord::Base.connection.execute(q).to_a
    end
  end
end
