# QueueClassicPlus

[![rainforestapp](https://circleci.com/gh/rainforestapp/queue_classic_plus.svg?branch=master)](https://app.circleci.com/pipelines/github/rainforestapp/queue_classic_plus?branch=master)

[queue_classic](https://github.com/QueueClassic/queue_classic) is a simple Postgresql backed DB queue. However, it's a little too simple to use it as the main queueing system of a medium to large app. This was developed at [Rainforest QA](https://www.rainforestqa.com/).

QueueClassicPlus adds many lacking features to QueueClassic.

- Standardized job format
- Retry on specific exceptions
- Singleton jobs
- Metrics
- Error logging / handling
- Transactions
- Rails generator to create new jobs

## Compatibility

This version of the matchers are compatible with queue_classic 3.1+ which includes built-in scheduling. See other branches for other compatible versions.

## Installation

Add these line to your application's Gemfile:

    gem 'queue_classic_plus'

And then execute:

    $ bundle

Run the migration

```ruby
  QueueClassicPlus.migrate
```

## Usage

### Create a new job

```bash
rails g qc_plus_job test_job
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

QueueClassicPlus ships with its own worker and a rake task to run it. You need to use this worker to take advance of many features of QueueClassicPlus.

```
QUEUE=low bundle exec qc_plus:work
```

### Other jobs options

#### Singleton Job

It's common for background jobs to never need to be enqueed multiple time. QueueClassicPlus support these type of single jobs. Here's an example one:

```ruby
class Jobs::UpdateMetrics < QueueClassicPlus::Base
  @queue = :low

  # Use the lock! keyword to prevent the job from being enqueud once.
  lock!

  def self.perform(metric_type)
    # ...
  end
end

```

Note that `lock!` only prevents the same job from beeing enqued multiple times if the argument match.

So in our example:

```ruby
Jobs::UpdateMetrics.do 'type_a' # enqueues job
Jobs::UpdateMetrics.do 'type_a' # does not enqueues job since it's already queued
Jobs::UpdateMetrics.do 'type_b' # enqueues job as the arguments are different.
```

#### Transactions

By default, all QueueClassicPlus jobs are executed in a PostgreSQL
transaction. This decision was made because most jobs are usually
pretty small and it's preferable to have all the benefits of the
transaction. You can optionally specify a postgres statement timeout
(in seconds) for all transactions with the environment variable
`POSTGRES_STATEMENT_TIMEOUT`.

You can disable this feature on a per job basis in the following way:

```ruby
class Jobs::NoTransaction < QueueClassicPlus::Base
  # Don't run the perform method in a transaction
  skip_transaction!
  @queue = :low

  def self.perform(user_id)
    # ...
  end
end
```


#### Callbacks

Jobs support the following callbacks:
```
before_enqueue
after_enqueue
before_perform
after_perform
```

- `enqueue` callbacks are called when the job is initially enqueued. Caveats:
  - not called on retries
  - not called when scheduled in the future (i.e. `Job.enqueue_perform_in`)
  - still called if enqueuing fails because a job with `lock!` is already enqueued. 
- `perform` callbacks are called any time the job is picked up and run by a worker, including retries and jobs scheduled in the future.

Callbacks can either be implemented by providing a method to be called:

```ruby
class Jobs::WithCallbackMethods < QueueClassicPlus::Base
  before_enqueue :before_enqueue_method

  @queue = :low

  def self.before_enqueue_method(*args)
    # ...
  end

  def self.perform(user_id)
    # ...
  end
end
```

or by providing a block:

```ruby
class Jobs::WithCallbackBlocks < QueueClassicPlus::Base
  before_enqueue do |*args|
    # ...
  end

  @queue = :low

  def self.perform(user_id)
    # ...
  end
end
```

The `args` passed to the callback method/block will be the same as the arguments passed to `QueueClassicPlus::Base.do` and `QueueClassicPlus::Base.perform`. 

## Advanced configuration

If you want to log exceptions in your favorite exception tracker. You can configured it like so:

```ruby
QueueClassicPlus.exception_handler = -> (exception, job) do
  Sentry.capture_exception(exception, extra: { job: job, env: ENV })
end
```

If you use Librato, we push useful metrics directly to them.

Push metrics to your metric provider (only Librato is supported for now).

```ruby
QueueClassicPlus.update_metrics
```

Call this in a cron job or something similar.

If you are using New Relic and want to push performance data to it, you can add this to an initializer:

```ruby
require "queue_classic_plus/new_relic"
```

To instrument Datadog monitoring add this to your QC initializer:

```ruby
require "queue_classic_plus/datadog"
```

The Datadog service name defaults to `qc.job`. This can be changed in the initializer: 

```ruby
QueueClassicDatadog.config.dd_service = "custom_service_name"
```

## Contributing

1. Fork it ( https://github.com/[my-github-username]/queue_classic_plus/fork )
- Create your feature branch (`git checkout -b my-new-feature`)
- Commit your changes (`git commit -am 'Add some feature'`)
- Push to the branch (`git push origin my-new-feature`)
- Create a new Pull Request

### Setting up the test database

```
createdb queue_classic_plus_test
```

## Releasing

Releasing is done in CircleCI via the `push_to_rubygems`, triggered by pushing a tagged commit.
You can create a new `tag` while [creating a new GitHub release](https://github.com/rainforestapp/queue_classic_plus/releases/new).

_** Note: The `tag` is what publishes a new version of the gem. The `release` is purely for documentation._
