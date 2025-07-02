# frozen_string_literal: true

require 'dry-configurable'

module QueueClassicDatadog
  extend Dry::Configurable

  setting :dd_service

  def _perform(*args)
    service_name = QueueClassicDatadog.config.dd_service || 'qc.job'

    Datadog::Tracing.trace('qc.job', service: service_name, resource: "#{name}#perform") do |_|
      super
    end
  end

  QueueClassicPlus::Base.singleton_class.send(:prepend, QueueClassicDatadog)
end
