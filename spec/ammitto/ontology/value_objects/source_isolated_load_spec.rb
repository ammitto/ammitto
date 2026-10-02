# frozen_string_literal: true

require 'spec_helper'

# `SourceEntityReference` has its own file, and `source_provenance.rb`
# requires it so callers that load only that file get the constant, and the
# two consumers require it directly. `spec_helper` loads `ammitto.rb`, which
# requires the whole tree, so a dropped require would only show up when a file
# is loaded by itself.
#
# Each example loads one file in a fresh process, because RSpec has already
# required the whole tree by the time an example runs.
RSpec.describe 'Ammitto::Ontology source provenance files' do
  include IsolatedLoadHelper

  %w[
    ammitto/ontology/value_objects/source_provenance
    ammitto/ontology/value_objects/source_entity_reference
    ammitto/ontology/entities/harmonized_entity
    ammitto/services/entity_resolution_service
  ].each do |path|
    it "loads #{path} on its own" do
      ok, err = load_in_subprocess(path)
      expect(ok).to be(true), "loading #{path} alone failed:\n#{err}"
    end
  end

  it 'defines SourceEntityReference when only source_provenance is required' do
    ok, err = load_in_subprocess('ammitto/ontology/value_objects/source_provenance',
                                 'Ammitto::Ontology::ValueObjects::SourceEntityReference.new')
    expect(ok).to be(true), err
  end
end
