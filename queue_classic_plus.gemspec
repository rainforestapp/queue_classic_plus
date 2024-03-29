# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'queue_classic_plus/version'

Gem::Specification.new do |spec|
  spec.name          = "queue_classic_plus"
  spec.version       = QueueClassicPlus::VERSION
  spec.authors       = ["Simon Mathieu", "Russell Smith", "Jean-Philippe Boily"]
  spec.email         = ["simon.math@gmail.com", "russ@rainforestqa.com", "j@jipi.ca"]
  spec.summary       = %q{Useful extras for Queue Classic}
  spec.description   = %q{}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "queue_classic", "4.0.0.pre.alpha1"
  spec.add_dependency "dry-configurable", "1.1.0"
  if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3.0')
    spec.add_development_dependency "bundler", "~> 1.6"
  else
    spec.add_development_dependency "bundler", "~> 2.0"
  end
  spec.add_development_dependency "rake"
  spec.add_development_dependency "activerecord", "~> 6.0"
  spec.add_development_dependency "activejob"
end
