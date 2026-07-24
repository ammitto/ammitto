# frozen_string_literal: true

require 'ammitto'

# Every lazily-required file must load: broken require_relative paths from
# the #16 restructure survived unnoticed because nothing exercised these
# files (services, cmd, harmonized entities). This spec fails on any
# LoadError the moment one regresses.
RSpec.describe 'lazily-required files load cleanly' do
  %w[
    ammitto/services/entity_resolution_service
    ammitto/cmd/china_command
    ammitto/ontology/entities/harmonized_entity
    ammitto/data/japan/schema_resolver
  ].each do |path|
    it "loads #{path}" do
      expect { require path }.not_to raise_error
    end
  end
end
