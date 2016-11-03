require 'spec_helper'

describe QueueClassicPlus::CustomWorker do
  let(:failed_queue) { described_class::FailedQueue }

  context "failure" do
    let(:queue) { QC::Queue.new("test") }
    let(:worker) { described_class.new q_name: queue.name }

    it "record failures in the failed queue" do
      queue.enqueue("Kerklfadsjflaksj", 1, 2, 3)
      failed_queue.count.should == 0
      worker.work
      failed_queue.count.should == 1
      job = failed_queue.lock
      job[:method].should == "Kerklfadsjflaksj"
      job[:args].should == [1, 2, 3]
      full_job = find_job(job[:id])

      full_job['last_error'].should_not be_nil
    end

    it "records normal errors" do
      queue.enqueue("Jobs::Tests::TestJobNoRetry.perform", true)
      failed_queue.count.should == 0
      worker.work
      failed_queue.count.should == 1
    end
  end

  context "retry" do
    let(:job_type) { Jobs::Tests::LockedTestJob }
    let(:worker) { described_class.new q_name: job_type.queue.name }
    let(:enqueue_expected_ts) { Time.now + described_class::BACKOFF_WIDTH }

    before do
      job_type.skip_transaction!
    end

    it "retries" do
      expect do
        job_type.enqueue_perform(true)
      end.to change_queue_size_of(job_type).by(1)

      Jobs::Tests::LockedTestJob.should have_queue_size_of(1)
      failed_queue.count.should == 0
      QueueClassicMatchers::QueueClassicRspec.find_by_args('low', 'Jobs::Tests::LockedTestJob._perform', [true]).first['remaining_retries'].should be_nil

      Timecop.freeze do
        worker.work

        failed_queue.count.should == 0 # not enqueued on Failed
        QueueClassicMatchers::QueueClassicRspec.find_by_args('low', 'Jobs::Tests::LockedTestJob._perform', [true]).first['remaining_retries'].should eq "4"
        Jobs::Tests::LockedTestJob.should have_scheduled(true).at(Time.now + described_class::BACKOFF_WIDTH) # should have scheduled a retry for later
      end

      Timecop.freeze(Time.now + (described_class::BACKOFF_WIDTH * 2)) do
        # the job should be re-enqueued with a decremented retry count
        jobs = QueueClassicMatchers::QueueClassicRspec.find_by_args('low', 'Jobs::Tests::LockedTestJob._perform', [true])
        jobs.size.should == 1
        job = jobs.first
        job['remaining_retries'].to_i.should == job_type.max_retries - 1
        job['locked_by'].should be_nil
        job['locked_at'].should be_nil
      end
    end

    [PG::UnableToSend, PG::ConnectionBad].each do |exception|
      context "with a #{exception} exception" do
        before do
          original_execute = QC.default_conn_adapter.method(:execute)
          allow(QC.default_conn_adapter).to receive(:execute) do |*args|
            if args.first == 'ROLLBACK'
              raise exception
            else
              original_execute.call(*args)
            end
          end
        end

        it 'retries without incrementing retries' do
          job_type.enqueue_perform(true)
          Timecop.freeze do
            worker.work
            expect(failed_queue.count).to eq 0
            QueueClassicMatchers::QueueClassicRspec.find_by_args('low', 'Jobs::Tests::LockedTestJob._perform', [true]).first['remaining_retries'].should eq "5"
          end
        end

        context 'with retries disabled for the class' do
          let(:job_type) { Jobs::Tests::TestJobNoRetry }

          it 'enqueues the failed queue' do
            job_type.enqueue_perform(true)
            Timecop.freeze do
              worker.work
              expect(failed_queue.count).to eq 1
            end
          end
        end
      end
    end

    context 'when retries have been exhausted' do
      before do
        job_type.max_retries = 0
      end

      after do
        job_type.max_retries = 5
      end

      it 'enqueues in the failed queue' do
        expect do
          job_type.enqueue_perform(true)
        end.to change_queue_size_of(job_type).by(1)

        Jobs::Tests::LockedTestJob.should have_queue_size_of(1)
        failed_queue.count.should == 0
        QueueClassicMatchers::QueueClassicRspec.find_by_args('low', 'Jobs::Tests::LockedTestJob._perform', [true]).first['remaining_retries'].should be_nil

        Timecop.freeze do
          worker.work

          QueueClassicMatchers::QueueClassicRspec.find_by_args('failed_jobs', 'Jobs::Tests::LockedTestJob._perform', [true]).first['remaining_retries'].should be_nil
          failed_queue.count.should == 1 # not enqueued on Failed
          Jobs::Tests::LockedTestJob.should_not have_scheduled(true).at(Time.now + described_class::BACKOFF_WIDTH) # should have scheduled a retry for later
        end
      end
    end
  end
end
