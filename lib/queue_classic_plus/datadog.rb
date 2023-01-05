# frozen_string_literal: true

module QueueClassicDatadog
  def _perform(*args)
    if Gem.loaded_specs['ddtrace'].version >= Gem::Version.new('1')
      Datadog::Tracing.trace('qc.job', service: 'qc.job', resource: "#{name}#perform") do |_|
        super
      end
    else
      Datadog.tracer.trace('qc.job', service_name: 'qc.job', resource: "#{name}#perform") do |_|
        super
      end
    end
  end

  QueueClassicPlus::Base.singleton_class.send(:prepend, QueueClassicDatadog)
end
