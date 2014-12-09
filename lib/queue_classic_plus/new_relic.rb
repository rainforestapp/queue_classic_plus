require 'new_relic/agent/method_tracer'

QueueClassicPlus::Base.class_eval do
  class << self
    include ::NewRelic::Agent::MethodTracer

    def new_relic_key
      "Custom/QueueClassicPlus/#{librato_key}"
    end

    def _perform_with_new_relic(*args)
      trace_execution_scoped([new_relic_key]) do
        _perform_without_new_relic *args
      end
    end

    alias_method_chain :_perform, :new_relic
  end
end
