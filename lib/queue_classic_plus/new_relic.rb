require 'new_relic/agent/method_tracer'

module QueueClassicNewRelic
  include NewRelic::Agent::Instrumentation::ControllerInstrumentation

  def new_relic_key
    "Custom/QueueClassicPlus/#{librato_key}"
  end

  def _perform(*args)
    opts = {
      name: 'perform',
      class_name: self.name,
      category: 'OtherTransaction/QueueClassicPlus',
    }

    perform_action_with_newrelic_trace(opts) do
      if NewRelic::Agent.config[:'queue_classic_plus.capture_params']
        NewRelic::Agent.add_custom_parameters(job_arguments: args)
      end

      super
    end
  end

  QueueClassicPlus::Base.singleton_class.send(:prepend, QueueClassicNewRelic)
end

QueueClassicPlus::CustomWorker.class_eval do
  def initialize(*)
    ::NewRelic::Agent.manual_start
    super
  end
end
