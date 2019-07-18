describe 'requiring queue_classic_plus/new_relic' do
  subject do
    Class.new(QueueClassicPlus::Base) do
      @queue = :test

      def self.perform
      end

      def self.name
        'Funky::Name'
      end
    end
  end

  it 'adds NewRelic profiling support' do
    expect(subject).to receive(:perform_action_with_newrelic_trace).once.with({
      name: 'perform',
      class_name: 'Funky::Name',
      category: 'OtherTransaction/QueueClassicPlus',
    })

    subject._perform
    require 'queue_classic_plus/new_relic'
    subject._perform
  end
end
