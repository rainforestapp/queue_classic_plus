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

  spec.add_dependency "queue_classic", "3.1.0.RC1"
  spec.add_dependency "activerecord", "> 3.0"
  spec.add_dependency "activesupport", "> 3.0"
  spec.add_dependency "with_advisory_lock"
  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
end
