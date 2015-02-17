require 'queue_classic_plus'
require 'pg'
require 'timecop'
require 'queue_classic_matchers'
require_relative './sample_jobs'

RSpec.configure do |config|
  config.before(:suite) do
    ActiveRecord::Base.establish_connection(
      :adapter  => "postgresql",
      :username => "postgres",
      :database => "queue_classic_plus_test",
      :host => 'localhost',
    )

    ActiveRecord::Base.connection.execute "drop schema public cascade; create schema public;"

    QC.default_conn_adapter = QC::ConnAdapter.new(ActiveRecord::Base.connection.raw_connection)
    QC::Setup.create
    QueueClassicPlus.migrate
  end

  config.before(:each) do
    tables = ActiveRecord::Base.connection.tables.select do |table|
      table != "schema_migrations"
    end
    ActiveRecord::Base.connection.execute("TRUNCATE #{tables.join(', ')} CASCADE") unless tables.empty?

  end
end
