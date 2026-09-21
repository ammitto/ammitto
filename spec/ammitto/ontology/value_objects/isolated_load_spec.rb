# frozen_string_literal: true

require 'spec_helper'

# Every harmonized value object must stand up on its own.
#
# Each one declares an attribute typed `SourceProvenance`, and that constant
# is resolved when the file is read, so a missing
# `require_relative 'source_provenance'` is a NameError the moment the file is
# loaded by itself. Nothing else would catch it: every spec and the harmonizer
# reach these files through `harmonized_entity.rb` and
# `entity_resolution_service.rb`, which require them in an order that happens
# to work.
#
# Each example loads one file in a fresh process, because RSpec has already
# required the whole tree by the time an example runs.
RSpec.describe 'Ammitto::Ontology::ValueObjects harmonized files' do
  include IsolatedLoadHelper

  files = %w[
    harmonized_address
    harmonized_birth_info
    harmonized_identification
    harmonized_name
    harmonized_nationality
  ]

  it 'covers every harmonized_* file in the directory' do
    on_disk = Dir[File.expand_path(
      '../../../../lib/ammitto/ontology/value_objects/harmonized_*.rb', __dir__
    )].map { |path| File.basename(path, '.rb') }

    expect(on_disk.sort).to eq(files.sort)
  end

  files.each do |name|
    it "loads ammitto/ontology/value_objects/#{name} on its own" do
      ok, err = load_in_subprocess("ammitto/ontology/value_objects/#{name}")
      expect(ok).to be(true), "loading #{name} alone failed:\n#{err}"
    end
  end
end
