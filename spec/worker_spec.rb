require 'spec_helper'

describe QueueClassicPlus::CustomWorker do
  let(:failed_queue) { described_class::FailedQueue }

  context "failure" do
    let(:queue) { QC::Queue.new("test") }
    let(:worker) { described_class.new q_name: queue.name }

    it "record failures in the failed queue" do
      queue.enqueue("Kerklfadsjflaksj", 1, 2, 3)
      expect(failed_queue.count).to eq(0)
      worker.work
      expect(failed_queue.count).to eq(1)
      job = failed_queue.lock
      expect(job[:method]).to eq("Kerklfadsjflaksj")
      expect(job[:args]).to eq([1, 2, 3])
      full_job = find_job(job[:id])

      expect(full_job['last_error']).to_not be_nil
    end

    it "records normal errors" do
      queue.enqueue("Jobs::Tests::TestJobNoRetry.perform", true)
      expect(failed_queue.count).to eq(0)
      worker.work
      expect(failed_queue.count).to eq(1)
    end

    context 'when Rails is defined', rails: true do
      let(:job_type) { Jobs::Tests::TestJobNoRetry }
      let(:queue) { job_type.queue }

      it 'properly serializes arguments for jobs in the failed queue' do
        job_type.enqueue_perform(:raise)
        expect(failed_queue.count).to eq(0)
        worker.work

        expect(failed_queue.count).to eq(1)
        job = QueueClassicMatchers::QueueClassicRspec.find_by_args(
          'failed_jobs',
          'Jobs::Tests::TestJobNoRetry._perform',
          [:raise]).first

        expect(job).to_not be_nil
        expect(job['last_error']).to_not be_nil
      end

      context 'for a non-QueueClassicPlus job' do
        let(:job_type) do
          Class.new(ActiveJob::Base) do
            def self.name
              "NonQcJob"
            end

            self.queue_adapter = :queue_classic

            queue_as :test

            def perform(boom)
              raise boom.to_s
            end
          end.tap { Object.const_set(:NonQcJob, _1) }
        end
        let(:queue) { QC::Queue.new("test") }

        it 'properly enqueues for jobs in the failed queue' do
          non_qc_job = job_type.new(:boom).enqueue
          job_id = non_qc_job.provider_job_id

          expect(failed_queue.count).to eq(0)
          job = find_job(job_id)
          expect(job).to_not be_nil
          expect(find_job(job_id.succ)).to be_nil
          args = JSON.load(job['args']).first
          expect(args['arguments']).to eq(QueueClassicPlus::Base.serialized([:boom]))

          worker.work

          expect(failed_queue.count).to eq(1)
          expect(find_job(job_id)).to be_nil
          job = find_job(job_id.succ)
          expect(job).to_not be_nil
          failed_args = JSON.load(job['args']).first
          expect(failed_args['arguments']).to eq(QueueClassicPlus::Base.serialized([:boom]))
          expect(job['last_error']).to_not be_nil
          expect(job['last_error']).to start_with("boom\n")
        end
      end
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

      expect(Jobs::Tests::LockedTestJob).to have_queue_size_of(1)
      expect(failed_queue.count).to eq(0)
      expect(QueueClassicMatchers::QueueClassicRspec.find_by_args('low', 'Jobs::Tests::LockedTestJob._perform', [true]).first['remaining_retries']).to be_nil

      expect(QueueClassicPlus::Metrics).to receive(:increment).with('qc.retry', source: nil )

      Timecop.freeze do
        worker.work

        expect(failed_queue.count).to eq(0) # not enqueued on Failed
        expect(QueueClassicMatchers::QueueClassicRspec.find_by_args('low', 'Jobs::Tests::LockedTestJob._perform', [true]).first['remaining_retries']).to eq "4"
        expect(Jobs::Tests::LockedTestJob).to have_scheduled(true).at(Time.now + described_class::BACKOFF_WIDTH) # should have scheduled a retry for later
      end

      Timecop.freeze(Time.now + (described_class::BACKOFF_WIDTH * 2)) do
        # the job should be re-enqueued with a decremented retry count
        jobs = QueueClassicMatchers::QueueClassicRspec.find_by_args('low', 'Jobs::Tests::LockedTestJob._perform', [true])
        expect(jobs.size).to eq(1)
        job = jobs.first
        expect(job['remaining_retries'].to_i).to eq(job_type.max_retries - 1)
        expect(job['locked_by']).to be_nil
        expect(job['locked_at']).to be_nil
      end
    end

    context 'when Rails is defined', rails: true do
      it 'retries' do
        expect do
          job_type.enqueue_perform(:foo)
        end.to change_queue_size_of(job_type).by(1)

        expect(Jobs::Tests::LockedTestJob).to have_queue_size_of(1)
        expect(failed_queue.count).to eq(0)
        expect(QueueClassicMatchers::QueueClassicRspec.find_by_args('low', 'Jobs::Tests::LockedTestJob._perform', [:foo]).first['remaining_retries']).to be_nil

        expect(QueueClassicPlus::Metrics).to receive(:increment).with('qc.retry', source: nil).twice

        Timecop.freeze do
          worker.work

          expect(failed_queue.count).to eq(0) # not enqueued on Failed
          expect(QueueClassicMatchers::QueueClassicRspec.find_by_args('low', 'Jobs::Tests::LockedTestJob._perform', [:foo]).first['remaining_retries']).to eq "4"
          expect(Jobs::Tests::LockedTestJob).to have_scheduled(:foo).at(Time.now + described_class::BACKOFF_WIDTH) # should have scheduled a retry for later
        end

        Timecop.freeze(Time.now + (described_class::BACKOFF_WIDTH * 2)) do
          # the job should be re-enqueued with a decremented retry count
          jobs = QueueClassicMatchers::QueueClassicRspec.find_by_args('low', 'Jobs::Tests::LockedTestJob._perform', [:foo])
          expect(jobs.size).to eq(1)
          job = jobs.first
          expect(job['remaining_retries'].to_i).to eq(job_type.max_retries - 1)
          expect(job['locked_by']).to be_nil
          expect(job['locked_at']).to be_nil
        end

        worker.work
      end
    end

    context 'when PG connection reaped during a job' do
      before { Jobs::Tests::ConnectionReapedTestJob.enqueue_perform }

      it 'retries' do
        expect(QueueClassicPlus::Metrics).to receive(:increment).with('qc.force_retry', source: nil )
        Timecop.freeze do
          worker.work
          expect(failed_queue.count).to eq 0
          expect(QueueClassicMatchers::QueueClassicRspec.find_by_args('low', 'Jobs::Tests::ConnectionReapedTestJob._perform', []).first['remaining_retries']).to eq "4"
        end
      end

      it 'ensures to rollback' do
        allow(QC.default_conn_adapter).to receive(:execute).and_call_original
        expect(QC.default_conn_adapter).to receive(:execute).with('ROLLBACK')
        Timecop.freeze do
          worker.work
        end
      end
    end

    context 'with a custom exception having max: 1 retry' do
      before { Jobs::Tests::TestJob.enqueue_perform(true) }

      it 'retries' do
        expect(QueueClassicPlus::Metrics).to receive(:increment).with('qc.retry', source: nil )
        Timecop.freeze do
          worker.work
          expect(failed_queue.count).to eq 0
          expect(QueueClassicMatchers::QueueClassicRspec.find_by_args('low', 'Jobs::Tests::TestJob._perform', [true]).first['remaining_retries']).to eq "0"
        end
      end
    end

    context 'with non-connection based PG jobs' do
      before { Jobs::Tests::UniqueViolationTestJob.enqueue_perform }

      it 'sends the job to the failed jobs queue' do
        Timecop.freeze do
          worker.work
        end
        expect(failed_queue.count).to eq 1
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

        expect(Jobs::Tests::LockedTestJob).to have_queue_size_of(1)
        expect(failed_queue.count).to eq(0)
        expect(QueueClassicMatchers::QueueClassicRspec.find_by_args('low', 'Jobs::Tests::LockedTestJob._perform', [true]).first['remaining_retries']).to be_nil

        Timecop.freeze do
          worker.work

          expect(QueueClassicMatchers::QueueClassicRspec.find_by_args('failed_jobs', 'Jobs::Tests::LockedTestJob._perform', [true]).first['remaining_retries']).to be_nil
          expect(failed_queue.count).to eq(1) # not enqueued on Failed
          expect(Jobs::Tests::LockedTestJob).to_not have_scheduled(true).at(Time.now + described_class::BACKOFF_WIDTH) # should have scheduled a retry for later
        end
      end
    end
  end
end
