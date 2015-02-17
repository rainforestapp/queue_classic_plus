# QueueClassicPlus

[![Build Status](https://travis-ci.org/rainforestapp/queue_classic_plus.svg?branch=master)](https://travis-ci.org/rainforestapp/queue_classic_plus)

QueueClassic is a simple Postgresql back DB queue. However, it's a little too simple to use it as the main queueing system of a medium to large app.

QueueClassicPlus adds many lacking features to QueueClassic.

- Standard job format
- Retry on specific exceptions
- Singleton jobs
- Metrics
- Error logging / handling
- Transactions

## Installation

Add these line to your application's Gemfile:

    gem 'queue_classic_plus'
    gem "queue_classic-later", github: "dpiddy/queue_classic-later"

And then execute:

    $ bundle

Run the migration

```ruby
  QueueClassicPlus.migrate
```

## Usage

### Create a new job

```bash
rails g my_job test_job
```

```ruby
# /app/jobs/my_job.rb
class Jobs::MyJob < QueueClassicPlus::Base
  # Specified the queue name
  @queue = :low

  # Extry up to 5 times when SomeException is raised
  retry! on: SomeException, max: 5

  def self.perform(a, b)
    # ...
  end
end

# In your code, you can enqueue this task like so:
Jobs::MyJob.do(1, "foo")

# You can also schedule a job in the future by doing

Jobs::MyJob.enqueue_perform_in(1.hour, 1, "foo")
```

### Run the QueueClassicPlus worker

```
QUEUE=low bundle exec qc_plus:work
```

## Advance configuration

If you want to log exceptions in your favorite exception tracker. You can configured it like sso:

```ruby
QueueClassicPlus.exception_handler = -> (exception, job) do
  Raven.capture_exception(exception, extra: {job: job, env: ENV})
end
```

If you use Librato, we push useful metrics directly to them.

Push metrics to your metric provider (only Librato is supported for now).

```ruby
QueueClassicPlus.update_metrics
```

Call this is a cron job or something similar.

If you are using NewRelic and want to push performance data to it, you can add this to an initializer:

```ruby
require "queue_classic_plus/new_relic"
```

## TODO

- Remove dep on ActiveRecord

## Contributing

1. Fork it ( https://github.com/[my-github-username]/queue_classic_plus/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
