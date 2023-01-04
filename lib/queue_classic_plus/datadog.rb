# frozen_string_literal: true

module QueueClassicDatadog
  def _perform(*args)
    Datadog::Tracing.trace('qc.job', service: 'qc.job', resource: "#{name}#perform") do |_|
      super
    end
  end

  QueueClassicPlus::Base.singleton_class.send(:prepend, QueueClassicDatadog)
end
