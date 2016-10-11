class SomeException < RuntimeError
end

class SomeOtherException < RuntimeError
end

module Jobs
  module Tests
    class LockedTestJob < QueueClassicPlus::Base
      lock!

      @queue = :low
      retry! on: SomeException, max: 5

      def self.perform should_raise
        raise SomeException if should_raise
      end
    end


    class TestJobNoRetry < QueueClassicPlus::Base
      class Custom < RuntimeError
      end
      disable_retries!

      @queue = :low

      def self.perform should_raise
        raise Custom if should_raise
      end
    end


    class TestJob < QueueClassicPlus::Base
      @queue = :low
      retry! on: SomeException, max: 5

      def self.perform should_raise
        raise SomeException if should_raise
      end
    end

  end
end
