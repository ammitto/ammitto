# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Ontology::Contracts do
  it 'reports a duplicate concept through the gem error hierarchy' do
    expect { described_class.define(:entity) }
      .to raise_error(Ammitto::ConfigurationError, /concept entity already defined/)
  end

  it 'reports a canonical class passed as a legacy facade through the gem error hierarchy' do
    expect { described_class.declare_legacy_attributes(Ammitto::Ontology::ValueObjects::NameVariant) }
      .to raise_error(Ammitto::ConfigurationError, /is not a legacy facade/)
  end

  it 'reports an unsupported transformer model through the gem error hierarchy' do
    expect { Ammitto::Transformers::CanonicalModels.build(String) }
      .to raise_error(Ammitto::ConfigurationError, /has no canonical contract/)
  end

  it 'keeps the nested conversion error as an alias of the centralized gem error' do
    expect(Ammitto::Ontology::Compatibility::ConflictError).to equal(Ammitto::CompatibilityConflictError)
    expect(Ammitto::CompatibilityConflictError.new('unrepresentable')).to be_a(Ammitto::Error)
  end
end
