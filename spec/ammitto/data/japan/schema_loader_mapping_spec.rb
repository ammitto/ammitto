# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/data/japan/schema_resolver'

RSpec.describe Ammitto::Data::Japan::SchemaLoader do
  # A mapping the resolver can never return is dead: no file is ever
  # validated against it, so it only misleads readers of the table.
  it 'maps exactly the schema types the resolver can return' do
    resolver = Ammitto::Data::Japan::SchemaResolver
    resolvable = [
      resolver.resolve('data/document-types.yml'),
      resolver.resolve('data/organizations.yml'),
      resolver.resolve('data/legal-instruments/fefta.yml'),
      resolver.resolve('data/sanction-lists/mof/notice.yml')
    ]

    expect(described_class.supported_types).to match_array(resolvable)
  end
end
