require 'queue_classic'
require "queue_classic_plus/version"
require "queue_classic_plus/metrics"
require "queue_classic_plus/base"
require "queue_classic_plus/worker"

module QueueClassicPlus
  require 'queue_classic_plus/railtie' if defined?(Rails)

  def self.migrate(c = QC::default_conn_adapter.connection)
    conn = QC::ConnAdapter.new(c)
    conn.execute("ALTER TABLE queue_classic_jobs ADD COLUMN last_error TEXT")
  end

  def self.demigrate(c = QC::default_conn_adapter.connection)
    conn = QC::ConnAdapter.new(c)
    conn.execute("ALTER TABLE queue_classic_jobs DROP COLUMN last_error")
  end
end
