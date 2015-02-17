require 'new_relic/agent/method_tracer'

QueueClassicPlus::Base.class_eval do
  class << self
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def new_relic_key
      "Custom/QueueClassicPlus/#{librato_key}"
    end

    def _perform_with_new_relic(*args)
      opts = {
        name: 'perform',
        class_name: self.name,
        category: 'OtherTransaction/QueueClassicPlus',
      }

      perform_action_with_newrelic_trace(opts) do
        if NewRelic::Agent.config[:'queue_classic_plus.capture_params']
          NewRelic::Agent.add_custom_parameters(job_arguments: args)
        end
        _perform_without_new_relic *args
      end
    end

    alias_method_chain :_perform, :new_relic
  end
end

QueueClassicPlus::CustomWorker.class_eval do
  def initialize(*)
    ::NewRelic::Agent.manual_start
    super
  end
end
