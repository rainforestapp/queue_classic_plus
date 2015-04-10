
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
        subject.should have_queue_size_of(1)
      end

      it "does allow multiple enqueues if something got locked for too long" do
        subject.do
        one_day_ago = Time.now - 60*60*24
        execute "UPDATE queue_classic_jobs SET locked_at = '#{one_day_ago}' WHERE q_name = 'test'"
        subject.do
        subject.should have_queue_size_of(2)
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
        QueueClassicPlus::Base.should_receive(:transaction).and_call_original
        subject._perform
      end

      it "measures the time" do
        QueueClassicPlus::Metrics.should_receive(:timing).with("qu_perform_time", {source: "funky.name"}).and_call_original
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
        QueueClassicPlus::Base.should_not_receive(:transaction)
        subject._perform
      end
    end

    context 'with isolation level' do
      subject do
        Class.new(QueueClassicPlus::Base) do
          @queue = :test
          isolation_level! :repeatable_read

          def self.perform
          end
        end
      end

      let(:transaction_sql) do
        'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ'
      end

      it 'sets the Postgres isolation level' do
        ['BEGIN', transaction_sql, 'COMMIT'].each do |statement|
          expect(QueueClassicPlus::Base).to receive(:execute).with statement
        end
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
        subject.retries_on?(SomeException.new).should be(true)
      end

      it "does not retry on unspecified exceptions" do
        subject.retries_on?(RuntimeError).should be(false)
      end

      it "sets max retries" do
        subject.max_retries.should == 5
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
        subject.retries_on?(SomeException.new).should be(true)
        subject.retries_on?(SomeOtherException.new).should be(true)
      end

      it "does not retry on unspecified exceptions" do
        subject.retries_on?(RuntimeError).should be(false)
      end

      it "sets max retries" do
        subject.max_retries.should == 5
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
        subject.retries_on?(ServiceReallyUnavailable.new).should be(true)
      end

      it "does not retry on unspecified exceptions" do
        subject.retries_on?(RuntimeError).should be(false)
      end

      it "sets max retries" do
        subject.max_retries.should == 5
      end
    end
  end

  describe ".librato_key" do
    it "removes unsupported caracter from the classname" do
      Jobs::Tests::TestJob.librato_key.should == 'jobs.tests.test_job'
    end
  end
end
