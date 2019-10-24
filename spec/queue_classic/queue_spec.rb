require 'spec_helper'

describe QC do

  describe ".lock" do

    context "lock" do

      it "locks the job with remaining_retries" do
        QC.enqueue_retry_in(1, "puts", 5, 2)
        sleep 1
        job = QC.lock

        expect(job[:q_name]).to eq("default")
        expect(job[:method]).to eq("puts")
        expect(job[:args][0]).to be(2)
        expect(job[:remaining_retries]).to eq("5")
      end
    end

  end

end
