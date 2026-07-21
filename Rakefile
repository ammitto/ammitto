# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

task default: :spec

namespace :export do
  desc 'Export all YAML data to JSON-LD format'
  task :jsonld do
    $LOAD_PATH.unshift(File.expand_path('lib', __dir__))
    require 'yaml'
    require 'json'
    require 'fileutils'
    require_relative 'lib/ammitto'

    puts 'Exporting YAML data to JSON-LD...'
    puts '-' * 50

    # Load and run exporter
    load File.expand_path('export.rb', __dir__)
  end

  desc 'Export a single source to JSON-LD (SOURCE=eu,un,us,wb)'
  task :source do
    $LOAD_PATH.unshift(File.expand_path('lib', __dir__))
    require 'yaml'
    require 'json'
    require 'fileutils'
    require_relative 'lib/ammitto'

    source = ENV['SOURCE']&.to_sym
    raise 'Please specify SOURCE=eu,un,us,wb' unless source

    puts "Exporting #{source.upcase} data to JSON-LD..."

    ARGV.clear
    ARGV << '--sources' << source.to_s << '--output' << '../data'
    load File.expand_path('export.rb', __dir__)
  end
end
