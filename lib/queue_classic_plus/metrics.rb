module QueueClassicPlus
  class Empty
    def self.method_missing(*)
      yield if block_given?
    end
  end

  class Metrics
    def self.timing(*args, &block)
      provider.timing *args, &block
    end

    def self.increment(*args)
      provider.increment(*args)
    end

    def self.measure(*args)
      provider.measure(*args)
    end

    def self.provider
      if defined?(Librato)
        Librato
      else
        Empty
      end
    end
  end
end
