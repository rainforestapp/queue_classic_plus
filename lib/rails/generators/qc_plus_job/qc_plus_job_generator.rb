class QcPlusJobGenerator < Rails::Generators::NamedBase
  source_root File.expand_path('../templates', __FILE__)

  def generate_lib
    template "job.rb.erb", File.join("app", "jobs", class_path, "#{file_name}.rb")
    if defined?(RSpec)
      template "job_spec.rb.erb", File.join("spec", "jobs", class_path, "#{file_name}_spec.rb")
    end
  end
end

