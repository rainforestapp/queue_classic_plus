require 'spec_helper'

describe QueueClassicPlus::UpdateMetrics do
  describe ".update" do
    it "works" do
      QC.enqueue "puts"

      expect(QueueClassicPlus::Metrics).to(receive(:measure)).at_least(1).times do |metric, value, options|
        expect(metric).to_not be_nil
        expect(value).to_not be_nil
      end
      described_class.update
    end
  end

  describe ".metrics" do
    subject { described_class.metrics }

    before do
      QC.enqueue "puts"
      QC.enqueue "puts", 2
      QC.enqueue_in 60, "puts", 2
    end

    context "jobs_queued" do
      it "returns the number of jobs group per queue" do
        expect(subject[:jobs_queued]).to eq([{"default" => 2}])
      end
    end

    context "jobs_scheduled" do
      it "returns the number of jobs group per queue" do
        expect(subject[:jobs_scheduled]).to eq([{"default" => 1}])
      end
    end

    context "max_locked_at" do
      it "zero if nothing is locked" do
        max = subject[:max_locked_at]
        expect(max).to eq(0)
      end

      it "returns the age of the oldest lock" do
        execute "UPDATE queue_classic_jobs SET locked_at = '#{Time.now - 60}'"

        max = subject[:max_locked_at]
        expect(59..61).to include(max)
      end

      context 'scheduled jobs' do
        it 'reports the correct max_locked_at' do
          execute "UPDATE queue_classic_jobs SET locked_at = '#{Time.now - 30}', scheduled_at = '#{Time.now - 60}', created_at = '#{Time.now - 5*60}'"

          expect(subject[:max_locked_at]).to eq 30
        end
      end
    end

    context "max_created_at" do
      it "returns a small positive value" do
        max = subject[:max_created_at]
        expect(0..0.2).to include(max)
      end

      context 'scheduled jobs' do
        it "ignores jobs schedule in the future" do
          execute "UPDATE queue_classic_jobs SET created_at = '#{Time.now - 60}', scheduled_at = '#{Time.now + 60}'"

          max = subject[:max_created_at]
          expect(0..0.2).to include(max)
        end

        context 'after scheduled_at is passed' do
          it 'reports time that the job has been ready' do
            execute "UPDATE queue_classic_jobs SET created_at = '#{Time.now - 5*60}', scheduled_at = '#{Time.now - 60}'"
            expect(subject[:max_created_at]).to eq 240
          end
        end
      end
    end

    context "max_created_at.unlocked" do
      it "ignores lock jobs" do
        execute "UPDATE queue_classic_jobs SET locked_at = '#{Time.now - 60}', created_at = '#{Time.now - 2*60}'"

        max = subject["max_created_at.unlocked"]
        expect(max).to eq(0)
      end
    end

    context "jobs_delayed.lag" do
      it "returns the maximum different between the scheduled time and now" do
        execute "UPDATE queue_classic_jobs SET scheduled_at = '#{Time.now - 60}'"

        lag = subject["jobs_delayed.lag"]
        expect(lag).to be_within(1.0).of(60)
      end

      it "ignores jobs scheduled in the future" do
        execute "UPDATE queue_classic_jobs SET scheduled_at = '#{Time.now + 60}'"

        lag = subject["jobs_delayed.lag"]
        expect(lag).to eq(0)
      end

      it "ignores the failed queue" do
        execute "UPDATE queue_classic_jobs SET scheduled_at = '#{Time.now - 60}', q_name = 'failed_jobs'"

        lag = subject["jobs_delayed.lag"]
        expect(lag).to eq(0)
      end
    end

    context "jobs_delayed.late_count" do
      it "returns the jobs that a created in the future" do
        count = subject["jobs_delayed.late_count"]
        # All jobs are always late because enqueue sets the value of
        # scheduled_at to now() for normal jobs
        expect(count).to eq(2)
      end
    end
  end
end
