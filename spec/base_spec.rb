require 'spec_helper'
require 'active_record'

describe QueueClassicPlus::Base do
  context "A child of QueueClassicPlus::Base" do
    subject do
      Class.new(QueueClassicPlus::Base) do
        @queue = :test
      end
    end

    it "allows multiple enqueues" do
      threads = []
      50.times do
        threads << Thread.new do
          subject.do
        end
      end
      threads.each(&:join)

      expect(subject).to have_queue_size_of(50)
    end

    context "that is locked" do
      subject do
        Class.new(QueueClassicPlus::Base) do
          @queue = :test
          lock!
        end
      end

      it "does not allow multiple enqueues" do
        threads = []
        50.times do
          threads << Thread.new do
            subject.do
            expect(subject).to have_queue_size_of(1)
          end
        end
        threads.each(&:join)
      end

      it "allows enqueueing same job with different arguments" do\
        threads = []
        (1..3).each do |arg|
          50.times do
            threads << Thread.new do
              subject.do(arg)
            end
          end
        end
        threads.each(&:join)

        expect(subject).to have_queue_size_of(3)
      end

      it "checks for an existing job using the same serializing as job enqueuing" do
        # simulate a case where obj#to_json and JSON.dump(obj) do not match
        require 'active_support/core_ext/date_time'
        require 'active_support/json'
        ActiveSupport::JSON::Encoding.use_standard_json_time_format = false

        date = DateTime.new(2020, 11, 3)
        subject.do(date)
        subject.do(date)
        expect(subject).to have_queue_size_of(1)
      end
    end

    context "when in a transaction" do
      subject do
        Class.new(QueueClassicPlus::Base) do
          @queue = :test
          lock!
        end
      end

      it "does not create another transaction when enqueueing" do
        conn = QC.default_conn_adapter.connection
        expect(conn).to receive(:transaction).exactly(1).times.and_call_original
        conn.transaction do
          subject.do
        end
      end
    end

    context "with default settings" do
      subject do
        Class.new(QueueClassicPlus::Base) do
          @queue = :test

          def self.perform
          end

          def self.name
            "Funky::Name"
          end
        end
      end

      it "calls perform in a transaction" do
        expect(QueueClassicPlus::Base).to receive(:transaction).and_call_original

        subject._perform
      end

      it "measures the time" do
        expect(QueueClassicPlus::Metrics).to receive(:timing).with("qu_perform_time", {source: "funky.name"}).and_call_original

        subject._perform
      end
    end

    context "skips transaction" do
      subject do
        Class.new(QueueClassicPlus::Base) do
          @queue = :test
          skip_transaction!

          def self.perform
          end
        end
      end

      it "calls perform outside of a transaction" do
        expect(QueueClassicPlus::Base).to_not receive(:transaction)

        subject._perform
      end
    end

    context "retries on single exception" do
      subject do
        Class.new(QueueClassicPlus::Base) do
          @queue = :test
          retry! on: SomeException, max: 5
          skip_transaction!

          def self.perform
          end
        end
      end

      it "retries on specified exception" do
        expect(subject.retries_on?(SomeException.new)).to be(true)
      end

      it "does not retry on unspecified exceptions" do
        expect(subject.retries_on?(RuntimeError)).to be(false)
      end

      it "sets max retries" do
        expect(subject.max_retries).to eq(5)
      end
    end

    context "retries on multiple exceptions" do
      subject do
        Class.new(QueueClassicPlus::Base) do
          @queue = :test
          retry! on: [SomeException, SomeOtherException], max: 5
          skip_transaction!

          def self.perform
          end
        end
      end

      it "retries on all specified exceptions" do
        expect(subject.retries_on?(SomeException.new)).to be(true)
        expect(subject.retries_on?(SomeOtherException.new)).to be(true)
      end

      it "does not retry on unspecified exceptions" do
        expect(subject.retries_on?(RuntimeError)).to be(false)
      end

      it "sets max retries" do
        expect(subject.max_retries).to eq(5)
      end
    end

    context "handles exception subclasses" do
      class ServiceReallyUnavailable < SomeException
      end

      subject do
        Class.new(QueueClassicPlus::Base) do
          @queue = :test
          retry! on: SomeException, max: 5
          skip_transaction!

          def self.perform
          end
        end
      end

      it "retries on a subclass of a specified exception" do
        expect(subject.retries_on?(ServiceReallyUnavailable.new)).to be(true)
      end

      it "does not retry on unspecified exceptions" do
        expect(subject.retries_on?(RuntimeError)).to be(false)
      end

      it "sets max retries" do
        expect(subject.max_retries).to eq(5)
      end
    end

    context "with Rails defined", rails: true do
      subject do
        Class.new(QueueClassicPlus::Base) do
          @queue = :test

          def self.perform(foo, bar)
          end
        end
      end

      it "serializes parameters when enqueuing a job" do
        expect(ActiveJob::Arguments).to receive(:serialize).with([42, true])

        subject.do(42, true)
      end

      it "deserializes parameters when performing an enqueued job" do
        expect(ActiveJob::Arguments).to receive(:deserialize).with([42, true]) { [42, true] }

        subject._perform(42, true)
      end
    end
  end

  describe ".librato_key" do
    it "removes unsupported caracter from the classname" do
      expect(Jobs::Tests::TestJob.librato_key).to eq('jobs.tests.test_job')
    end
  end

  context 'with ActiveRecord' do
    before do
      @old_conn_adapter = QC.default_conn_adapter
      @activerecord_conn = ActiveRecord::Base.establish_connection(ENV["DATABASE_URL"])
      QC.default_conn_adapter = QC::ConnAdapter.new(
        connection: ActiveRecord::Base.connection.raw_connection
      )
    end

    after do
      @activerecord_conn.disconnect!
      QC.default_conn_adapter = @old_conn_adapter
    end

    subject do
      Class.new(QueueClassicPlus::Base) do
        @queue = :test

        def self.perform(foo, bar)
        end
      end
    end

    it 'works' do
      expect { subject._perform(1, 2) }.not_to raise_error
    end
  end
end
