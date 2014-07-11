require 'rails'

module MyPlugin
  class Railtie < Rails::Railtie
    railtie_name :queue_classic_plus

    rake_tasks do
      load "queue_classic_plus/tasks/work.rake"
    end
  end
end

