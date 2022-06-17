# frozen_string_literal: true

module QueueClassicDatadog
  def _perform(*args)
    # Datadog::VERSION was moved to DDTrace::VERSION in dd_trace 1.0
    tracer, options =
      if defined?(Datadog::VERSION)
        [Datadog.tracer, { service_name: 'qc.job', resource: "#{name}#perform" }]
      else
        [Datadog::Tracing, { service: 'qc.job', resource: "#{name}#perform" }]
      end

    tracer.trace('qc.job', **options) do |_|
      super
    end
  end

  QueueClassicPlus::Base.singleton_class.send(:prepend, QueueClassicDatadog)
end
