module QueueClassicPlus
  class Base
    extend QueueClassicPlus::InheritableAttribute

    def self.queue
      QC::Queue.new(@queue)
    end

    inheritable_attr :locked
    inheritable_attr :skip_transaction
    inheritable_attr :retries_on
    inheritable_attr :max_retries
    inheritable_attr :disable_retries

    self.max_retries = 5
    self.retries_on = {}
    self.disable_retries = false

    def self.retry!(on: RuntimeError, max: 5)
      if self.disable_retries
        raise 'retry! should not be used in conjuction with disable_retries!'
      end
      Array(on).each {|e| self.retries_on[e] = true}
      self.max_retries = max
    end

    def self.retries_on? exception
      self.retries_on[exception.class] || self.retries_on.keys.any? {|klass| exception.is_a? klass}
    end

    def self.disable_retries!
      unless self.retries_on.empty?
        raise 'disable_retries! should not be enabled in conjunction with retry!'
      end

      self.disable_retries = true
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
                 LIMIT 1
               )
             AS x"

        result = QC.default_conn_adapter.execute(q, @queue, method, JSON.dump(serialized(args)))
        result['count'].to_i == 0
      else
        true
      end
    end

    def self.enqueue(method, *args)
      if can_enqueue?(method, *args)
        queue.enqueue(method, *serialized(args))
      end
    end

    def self.enqueue_perform(*args)
      enqueue("#{self.to_s}._perform", *args)
    end

    def self.enqueue_perform_in(time, *args)
      raise "Can't enqueue in the future for locked jobs" if locked?
      queue.enqueue_in(time, "#{self.to_s}._perform", *serialized(args))
    end

    def self.restart_in(time, remaining_retries, *args)
      queue.enqueue_retry_in(time, "#{self.to_s}._perform", remaining_retries, *serialized(args))
    end

    def self.do(*args)
      Metrics.timing("qc_enqueue_time", source: librato_key) do
        enqueue_perform(*args)
      end
    end

    def self._perform(*args)
      Metrics.timing("qu_perform_time", source: librato_key) do
        if skip_transaction
          perform(*deserialized(args))
        else
          transaction do
            # .to_i defaults to 0, which means no timeout in postgres
            timeout = ENV['POSTGRES_STATEMENT_TIMEOUT'].to_i * 1000
            execute "SET LOCAL statement_timeout = #{timeout}"
            perform(*deserialized(args))
          end
        end
      end
    end

    def self.librato_key
      Inflector.underscore(self.name || "").gsub(/\//, ".")
    end

    def self.transaction(options = {}, &block)
      if defined?(ActiveRecord) && ActiveRecord::Base.connected?
        # If ActiveRecord is loaded, we use it's own transaction mechanisn since
        # it has slightly different semanctics for rollback.
        ActiveRecord::Base.transaction(**options, &block)
      else
        begin
          execute "BEGIN"
          block.call
        rescue
          execute "ROLLBACK"
          raise
        end

        execute "COMMIT"
      end
    end

    def self.before_enqueue(callback_method = nil, &block)
      define_callback(:enqueue, :before, callback_method, &block)
    end

    def self.after_enqueue(callback_method = nil, &block)
      define_callback(:enqueue, :after, callback_method, &block)
    end

    def self.before_perform(callback_method = nil, &block)
      define_callback(:perform, :before, callback_method, &block)
    end

    def self.after_perform(callback_method = nil, &block)
      define_callback(:perform, :after, callback_method, &block)
    end

    # Debugging
    def self.list
      q = "SELECT * FROM queue_classic_jobs WHERE q_name = '#{@queue}'"
      execute q
    end

    protected

    def self.serialized(args)
      if defined?(Rails)
        ActiveJob::Arguments.serialize(args)
      else
        args
      end
    end

    def self.deserialized(args)
      if defined?(Rails)
        ActiveJob::Arguments.deserialize(args)
      else
        args
      end
    end

    private

    def self.execute(sql, *args)
      QC.default_conn_adapter.execute(sql, *args)
    end

    def self.define_callback(name, type, callback_method, &_block)
      singleton_class.prepend(
        Module.new do |callback_module|
          callback_module.define_method(name) do |*args|
            callback_args = args
              if name == :enqueue
                callback_args = callback_args.drop(1) # Class/method is the first argument. Callbacks don't need that.
              end

              if type == :before
                block_given? ? yield(*callback_args) : send(callback_method, *callback_args)
              end
              super(*args)
              if type == :after
                block_given? ? yield(*callback_args) : send(callback_method, *callback_args)
              end
          end
        end
      )
    end
  end
end
