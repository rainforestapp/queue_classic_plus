require 'spec_helper'
require 'active_record'

describe QC do
  describe ".lock" do
    context "with a connection from ActiveRecord that casts return types" do
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
