# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

task default: :spec

# The former export:jsonld / export:source tasks loaded a root-level
# export.rb that was removed in a5124d3; use `ammitto harmonize` /
# `ammitto export` instead.
