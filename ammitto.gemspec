# frozen_string_literal: true

require_relative 'lib/ammitto/version'

Gem::Specification.new do |spec|
  spec.name          = 'ammitto'
  spec.version       = Ammitto::VERSION
  spec.authors       = ['Ribose Inc.']
  spec.email         = ['open.source@ribose.com']
  spec.homepage      = 'https://github.com/ammitto/ammitto'
  spec.licenses      = 'BSD-2-Clause'
  spec.summary       = 'Ammitto: retrieve sanctioned entities from international sources'
  spec.description   = 'Ammitto retrieves sanctioned people, organizations, vessels, and ' \
                       'aircraft from various international sources including EU, UN, US, ' \
                       'World Bank, and more.'

  spec.files         = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.platform      = Gem::Platform::RUBY
  spec.require_paths = ['lib']
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.required_ruby_version = Gem::Requirement.new('>= 2.7.0')

  # Core dependencies
  spec.add_dependency 'csv'
  spec.add_dependency 'faraday', '~> 2.0'
  spec.add_dependency 'json-ld', '~> 3.3'
  spec.add_dependency 'lutaml-model', '~> 0.7'
  spec.add_dependency 'mechanize', '~> 2.12'
  spec.add_dependency 'moxml'
  spec.add_dependency 'multi_json', '~> 1.15'
  spec.add_dependency 'nokogiri', '>= 1.15'
  spec.add_dependency 'rdf', '~> 3.3'
  spec.add_dependency 'rdf-turtle', '~> 3.3'
  spec.add_dependency 'roo', '~> 2.10'
  spec.add_dependency 'thor', '~> 1.3'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
