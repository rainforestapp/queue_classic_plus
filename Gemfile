source 'https://rubygems.org'

# Specify your gem's dependencies in queue_classic_plus.gemspec
gemspec

gem "queue_classic_matchers", github: 'rainforestapp/queue_classic_matchers'
gem 'pry'

group :development do
  gem "guard-rspec", require: false
  gem "terminal-notifier-guard"
end

group :test do
  gem 'byebug'
  gem 'rspec'
  gem 'timecop'
  gem 'newrelic_rpm'
  gem 'ddtrace'
end
