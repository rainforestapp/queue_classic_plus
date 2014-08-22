require 'spec_helper'

describe QueueClassicPlus::CustomWorker do
  class QueueClassicLaterJob < ActiveRecord::Base
  end

  class QueueClassicJob < ActiveRecord::Base
  end

  let(:failed_queue) { described_class::FailedQueue }

  before do
    ActiveRecord::Base.connection.execute "DELETE FROM queue_classic_jobs"
    ActiveRecord::Base.connection.execute "DELETE FROM queue_classic_later_jobs"
  end

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
      QueueClassicJob.last.last_error.should be_present
    end

    it "records normal errors" do
      queue.enqueue("Jobs::Test::TestJobNoRetry.perform", true)
      failed_queue.count.should == 0
      worker.work
      failed_queue.count.should == 1
    end
  end

  context "retry" do
    let(:job_type) { Jobs::Test::LockedTestJob }
    let(:worker) { described_class.new q_name: job_type.queue.name }
    let(:enqueue_expected_ts) { described_class::BACKOFF_WIDTH.seconds.from_now }

    before do
      job_type.skip_transaction!
    end

    it "retries" do
      expect do
        job_type.enqueue_perform(true)
      end.to change_queue_size_of(job_type).by(1)

      Jobs::Test::LockedTestJob.should have_queue_size_of(1)
      failed_queue.count.should == 0
      QueueClassicMatchers::QueueClassicRspec.find_by_args('mturk', 'Jobs::Test::LockedTestJob._perform', [true]).first['remaining_retries'].should be_nil

      Timecop.freeze do
        expect do
          worker.work
        end.to change_queue_size_of(job_type).by(-1)

        failed_queue.count.should == 0 # not enqueued on Failed
        Jobs::Test::LockedTestJob.should have_scheduled(true).at(Time.now + described_class::BACKOFF_WIDTH.seconds.to_i) # should have scheduled a retry for later
      end

      Timecop.freeze(Time.now + (described_class::BACKOFF_WIDTH.seconds.to_i * 2)) do
        QC::Later.tick(true)
        # the job should be re-enqueued with a decremented retry count
        jobs = QueueClassicMatchers::QueueClassicRspec.find_by_args('mturk', 'Jobs::Test::LockedTestJob._perform', [true])
        jobs.size.should == 1
        job = jobs.first
        job['remaining_retries'].to_i.should == job_type.max_retries - 1
        job['locked_by'].should be_nil
        job['locked_at'].should be_nil
      end
    end

    it "enqueues in the failed queue when retries have been exhausted" do
      job_type.max_retries = 0
      expect do
        job_type.enqueue_perform(true)
      end.to change_queue_size_of(job_type).by(1)

      Jobs::Test::LockedTestJob.should have_queue_size_of(1)
      failed_queue.count.should == 0
      QueueClassicMatchers::QueueClassicRspec.find_by_args('mturk', 'Jobs::Test::LockedTestJob._perform', [true]).first['remaining_retries'].should be_nil

      Timecop.freeze do
        expect do
          worker.work
        end.to change_queue_size_of(job_type).by(-1)

        failed_queue.count.should == 1 # not enqueued on Failed
        Jobs::Test::LockedTestJob.should_not have_scheduled(true).at(Time.now + described_class::BACKOFF_WIDTH.seconds.to_i) # should have scheduled a retry for later
      end
    end
  end

  context "enqueuing during a retry" do
    let(:job_type) { Jobs::Test::LockedTestJob }
    let(:worker) { described_class.new q_name: job_type.queue.name }
    let(:enqueue_expected_ts) { described_class::BACKOFF_WIDTH.seconds.from_now }

    before do
      job_type.max_retries = 5
      job_type.skip_transaction!
    end

    it "does not enqueue in main queue while retrying" do
      expect do
        job_type.enqueue_perform(true)
      end.to change_queue_size_of(job_type).by(1)

      Jobs::Test::LockedTestJob.should have_queue_size_of(1)
      failed_queue.count.should == 0
      QueueClassicMatchers::QueueClassicRspec.find_by_args('mturk', 'Jobs::Test::LockedTestJob._perform', [true]).first['remaining_retries'].should be_nil

      Timecop.freeze do
        expect do
          worker.work
        end.to change_queue_size_of(job_type).by(-1)

        failed_queue.count.should == 0 # not enqueued on Failed
        Jobs::Test::LockedTestJob.should have_scheduled(true).at(Time.now + described_class::BACKOFF_WIDTH.seconds.to_i) # should have scheduled a retry for later

        expect do
          job_type.enqueue_perform(true)
        end.to change_queue_size_of(job_type).by(0)
      end
    end
  end
end

