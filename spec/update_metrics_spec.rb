require 'spec_helper'

describe QueueClassicPlus::UpdateMetrics do
  class QueueClassicJob < ActiveRecord::Base
  end

  describe ".update" do
    it "works" do
      QC.enqueue "puts"

      expect(QueueClassicPlus::Metrics).to(receive(:measure)).at_least(1).times do |metric, value, options|
        expect(metric).to be_present
        expect(value).to be_present
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
        ActiveRecord::Base.connection.execute "
          UPDATE queue_classic_jobs SET locked_at = '#{1.minute.ago}'
        "

        max = subject[:max_locked_at]
        expect(59..61).to include(max)
      end

      context 'scheduled jobs' do
        it 'reports the correct max_locked_at' do
          qc_job = QueueClassicJob.last
          qc_job.update(created_at: 5.minutes.ago,
                        scheduled_at: 1.minutes.ago,
                        locked_at: 30.seconds.ago)

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
          ActiveRecord::Base.connection.execute "
            UPDATE queue_classic_jobs SET created_at = '#{1.minute.ago}', scheduled_at = '#{1.minutes.from_now}'
          "

          max = subject[:max_created_at]
          expect(0..0.2).to include(max)
        end

        context 'after scheduled_at is passed' do
          it 'reports time that the job has been ready' do
            QueueClassicJob.last.update(created_at: 5.minutes.ago, scheduled_at: 1.minutes.ago)
            expect(subject[:max_created_at]).to eq 240
          end
        end
      end
    end

    context "max_created_at.unlocked" do
      it "ignores lock jobs" do
        ActiveRecord::Base.connection.execute "
          UPDATE queue_classic_jobs SET locked_at = '#{1.minute.ago}', created_at = '#{2.minutes.ago}'
        "

        max = subject["max_created_at.unlocked"]
        expect(max).to eq(0)
      end
    end

    context "jobs_delayed.lag" do
      it "returns the maximum different between the scheduled time and now" do
        ActiveRecord::Base.connection.execute "
          UPDATE queue_classic_jobs SET scheduled_at = '#{1.minute.ago}'"

        lag = subject["jobs_delayed.lag"]
        expect(lag).to be_within(1.0).of(60)
      end

      it "ignores jobs scheduled in the future" do
        ActiveRecord::Base.connection.execute "
          UPDATE queue_classic_jobs SET scheduled_at = '#{1.minute.from_now}'"

        lag = subject["jobs_delayed.lag"]
        expect(lag).to eq(0)
      end

      it "ignores the failed queue" do
        ActiveRecord::Base.connection.execute "
          UPDATE queue_classic_jobs SET scheduled_at = '#{1.minute.ago}', q_name = 'failed_jobs'"

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
