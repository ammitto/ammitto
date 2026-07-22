# frozen_string_literal: true

require 'ammitto'
require 'ammitto/data/japan/schema_resolver'

# Pins the substring-based directory detection in the schema resolvers.
# These checks (LIST.any? { |dir| path.include?(dir) }) were once
# miscorrected by an unsafe autocorrect into Array#intersect? with a String
# argument, which raises TypeError — this spec fails loudly if that returns.
RSpec.describe 'schema resolver path detection' do
  it 'resolves China legal-instrument paths by directory substring' do
    expect(
      Ammitto::Data::China::SchemaResolver.resolve('sources/legal-instruments/2024-01.yml')
    ).to eq(:legal_instrument)
  end

  it 'resolves Japan legal-instrument paths by directory substring' do
    expect(
      Ammitto::Data::Japan::SchemaResolver.resolve('sources/legal-instruments/2024-01.yml')
    ).to eq(:legal_instrument)
  end
end
