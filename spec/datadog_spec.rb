describe 'requiring queue_classic_plus/new_relic' do
  class FunkyName < QueueClassicPlus::Base
    @queue = :test

    def self.perform
    end
  end

  subject { FunkyName._perform }

  it 'adds Datadog profiling support' do
    require 'queue_classic_plus/datadog'
    expect(Datadog::Tracing).to receive(:trace).with(
      'qc.job', service: 'qc.job', resource: 'FunkyName#perform'
    )
    subject
  end

  context "when service name is configured" do
    let(:configured_service_name) { "configured_service_name" }

    it "traces using the service name" do
      require 'queue_classic_plus/datadog'
      QueueClassicDatadog.config.dd_service = configured_service_name

      expect(Datadog::Tracing).to receive(:trace).with(
        'qc.job', service: configured_service_name, resource: 'FunkyName#perform'
      )
      subject
    end
  end
end
