# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

# Shared temporary source-directory lifecycle for harmonize specs.
module HarmonizeSourcesDir
  def self.included(example_group)
    example_group.let(:sources_dir) do
      Dir.mktmpdir('ammitto_harmonize_test')
    end
    example_group.after do
      FileUtils.rm_rf(sources_dir)
    end
  end
end
