# frozen_string_literal: true
lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require_relative "lib/ammitto/version"

Gem::Specification.new do |s|
  s.name          = "ammitto"
  s.version       = Ammitto::VERSION
  s.authors       = ["Ribose Inc."]
  s.email         = ["open.source@ribose.com"]
  s.homepage      = "https://github.com/ammitto/ammitto"
  s.licenses      = "BSD-2-Clause"
  s.summary       = "Amitto: retrieve sanctioned people and organizations from various published sources"
  s.description   = "Amitto: retrieve sanctioned people and organizations from various published sources"

  s.files         = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  s.platform      = Gem::Platform::RUBY
  s.require_paths = ["lib"]
  s.required_ruby_version = Gem::Requirement.new(">= 2.4.0")

  s.add_dependency "nokogiri", '1.10.10'
  s.add_development_dependency "equivalent-xml", "~> 0.6"

end


