require 'pg'

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

    class Exception < RuntimeError
      attr_reader :original_exception

      def initialize(e)
        @original_exception = e
      end
    end

    class ConnectionReapedTestJob < QueueClassicPlus::Base
      @queue = :low
      retry! on: Exception, max: 5

      def self.perform
        raise Exception.new(PG::UnableToSend.new)
      end
    end

    class UniqueViolationTestJob < QueueClassicPlus::Base
      @queue = :low

      def self.perform
        raise Exception.new(PG::UniqueViolation.new)
      end
    end
  end
end
