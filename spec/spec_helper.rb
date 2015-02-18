require 'queue_classic_plus'
require 'pg'
require 'timecop'
require 'queue_classic_matchers'
require_relative './sample_jobs'
require_relative './helpers'
require 'pry'

ENV["DATABASE_URL"] ||= "postgres:///queue_classic_plus_test"

RSpec.configure do |config|
  config.include QcHelpers

  config.before(:suite) do
    QC.default_conn_adapter.execute "drop schema public cascade; create schema public;"

    QC::Setup.create
    QueueClassicPlus.migrate
  end

  config.before(:each) do
    QC.default_conn_adapter.execute "TRUNCATE queue_classic_jobs;"
  end
end
