require 'spec_helper'
require 'active_record'

describe QueueClassicPlus::Base do
  context "A child of QueueClassicPlus::Base" do
    context "that is locked" do
      subject do
        Class.new(QueueClassicPlus::Base) do
          @queue = :test
          lock!
        end
      end

      it "does not allow multiple enqueues" do
        subject.do
        subject.do
        expect(subject).to have_queue_size_of(1)
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

      it "does allow multiple enqueues if something got locked for too long" do
        subject.do
        one_day_ago = Time.now - 60*60*24
        execute "UPDATE queue_classic_jobs SET locked_at = '#{one_day_ago}' WHERE q_name = 'test'"
        subject.do
        expect(subject).to have_queue_size_of(2)
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

    context "with callbacks defined" do
      subject do
        Class.new(QueueClassicPlus::Base) do
          @queue = :test

          before_enqueue :before_enqueue_method
          after_enqueue :after_enqueue_method
          around_enqueue :around_enqueue_method

          before_perform :before_perform_method
          after_perform :after_perform_method
          around_perform :around_perform_method

          def self.before_enqueue_method(*_args); end;
          def self.after_enqueue_method(*_args); end;
          def self.around_enqueue_method(*_args); end;
          def self.before_perform_method(*_args); end;
          def self.after_perform_method(*_args); end;
          def self.around_perform_method(*_args); end;

          def self.perform(*_args); end;
        end
      end

      it "passes enqueue arguments to callbacks" do
        expect(subject).to receive(:before_enqueue_method).with("enqueue_argument").once
        expect(subject).to receive(:after_enqueue_method).with("enqueue_argument").once
        expect(subject).to receive(:around_enqueue_method).with("enqueue_argument").exactly(2).times

        subject.do("enqueue_argument")
      end

      it "passes perform arguments to callbacks" do
        expect(subject).to receive(:before_perform_method).with("perform_argument").once
        expect(subject).to receive(:after_perform_method).with("perform_argument").once
        expect(subject).to receive(:around_perform_method).with("perform_argument").exactly(2).times

        subject.perform("perform_argument")
      end

      context "when enqueued" do
        it "calls the enqueue callback methods" do
          expect(subject).to receive(:before_enqueue_method).once
          expect(subject).to receive(:after_enqueue_method).once
          expect(subject).to receive(:around_enqueue_method).exactly(2).times

          subject.do
        end

        it "does not call the perform callbacks" do
          expect(subject).to_not receive(:before_perform_method)
          expect(subject).to_not receive(:after_perform_method)
          expect(subject).to_not receive(:around_perform_method)

          subject.do
        end
      end

      context "when perform" do
        it "calls the perform callback methods" do
          expect(subject).to receive(:before_perform_method).once
          expect(subject).to receive(:after_perform_method).once
          expect(subject).to receive(:around_perform_method).exactly(2).times

          subject.perform
        end

        it "does not call the enqueue callbacks" do
          expect(subject).to_not receive(:before_enqueue_method)
          expect(subject).to_not receive(:after_enqueue_method)
          expect(subject).to_not receive(:around_enqueue_method)

          subject.perform
        end
      end

      context "when callback defined multiple times" do
        subject do
          Class.new(QueueClassicPlus::Base) do
            @queue = :test

            before_enqueue :before_enqueue_method_1
            before_enqueue :before_enqueue_method_2
            before_enqueue :before_enqueue_method_3

            def self.before_enqueue_method_1(*_args); end;
            def self.before_enqueue_method_2(*_args); end;
            def self.before_enqueue_method_3(*_args); end;

            def self.perform(*_args); end;
          end
        end

        it "calls each callback" do
          expect(subject).to receive(:before_enqueue_method_1).once
          expect(subject).to receive(:before_enqueue_method_2).once
          expect(subject).to receive(:before_enqueue_method_3).once

          subject.do
        end
      end
    end

    context "with callback blocks defined" do
      subject do
        Class.new(QueueClassicPlus::Base) do
          @queue = :test
          class_variable_set(:@@block_result, [])

          before_enqueue do |*_args|
            class_variable_get(:@@block_result).append("before_enqueue_block")
          end
          after_enqueue do |*_args|
            class_variable_get(:@@block_result).append("after_enqueue_block")
          end
          around_enqueue do |*_args|
            class_variable_get(:@@block_result).append("around_enqueue_block")
          end

          before_perform do |*_args|
            class_variable_get(:@@block_result).append("before_perform_block")
          end
          after_perform do |*_args|
            class_variable_get(:@@block_result).append("after_perform_block")
          end
          around_perform do |*_args|
            class_variable_get(:@@block_result).append("around_perform_block")
          end

          def self.perform; end;
        end
      end

      context "when enqueued" do
        it "calls the enqueue callback blocks" do
          subject.do

          expect(subject.class_variable_get(:@@block_result)).to eq(
            %w(around_enqueue_block before_enqueue_block after_enqueue_block around_enqueue_block)
          )
        end
      end

      context "when perform" do
        it "calls the perform callback blocks" do
          subject.perform

          expect(subject.class_variable_get(:@@block_result)).to eq(
            %w(around_perform_block before_perform_block after_perform_block around_perform_block)
          )
        end
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
