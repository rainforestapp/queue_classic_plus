describe 'requiring queue_classic_plus/new_relic' do
  class FunkyName < QueueClassicPlus::Base
    @queue = :test

    def self.perform
    end
  end

  subject { FunkyName._perform }

  it 'adds Datadog profiling support' do
    require 'queue_classic_plus/datadog'
    expect(Datadog.tracer).to receive(:trace).with(
      'qc.job', service_name: 'qc.job', resource: 'FunkyName#perform'
    )
    subject
  end
end
