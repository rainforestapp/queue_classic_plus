source 'https://rubygems.org'

# Specify your gem's dependencies in queue_classic_plus.gemspec
gemspec



gem 'pg'
gem "queue_classic_matchers", github: 'rainforestapp/queue_classic_matchers', branch: 'qc-3-1-compatible'
gem 'pry'

group :development do
  gem "guard-rspec", require: false
  gem "terminal-notifier-guard"
end

group :test do
  gem 'rspec'
  gem 'timecop'
end
