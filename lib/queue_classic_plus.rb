require 'logger'
require "queue_classic"

require "queue_classic_plus/version"
require "queue_classic_plus/inheritable_attr"
require "queue_classic_plus/inflector"
require "queue_classic_plus/metrics"
require "queue_classic_plus/update_metrics"
require "queue_classic_plus/base"
require "queue_classic_plus/worker"
require "queue_classic_plus/queue_classic/queue"

module QueueClassicPlus
  require 'queue_classic_plus/railtie' if defined?(Rails)

  def self.migrate(c = QC::default_conn_adapter.connection)
    conn = QC::ConnAdapter.new(c)
    conn.execute("ALTER TABLE queue_classic_jobs ADD COLUMN last_error TEXT")
    conn.execute("ALTER TABLE queue_classic_jobs ADD COLUMN remaining_retries INTEGER")
  end

  def self.demigrate(c = QC::default_conn_adapter.connection)
    conn = QC::ConnAdapter.new(c)
    conn.execute("ALTER TABLE queue_classic_jobs DROP COLUMN last_error")
    conn.execute("ALTER TABLE queue_classic_jobs DROP COLUMN remaining_retries")
  end

  def self.exception_handler
    @exception_handler ||= -> (exception, job) { nil }
  end

  def self.exception_handler=(handler)
    @exception_handler = handler
  end

  def self.update_metrics
    UpdateMetrics.update
  end

  def self.logger
    @logger ||= defined?(Rails) ? Rails.logger : Logger.new(STDOUT)
  end

  def self.logger=(l)
    @logger = l
  end
end
