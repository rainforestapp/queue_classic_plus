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
  gem 'datadog'
  gem 'simplecov', require: false

  # Ruby 3.3+ extracted these from stdlib
  if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.3.0')
    gem 'mutex_m'
    gem 'base64'
    gem 'bigdecimal'
    gem 'drb'
  end
end
