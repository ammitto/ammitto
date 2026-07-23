# frozen_string_literal: true

require 'ammitto'

RSpec.describe Ammitto::Ontology::Entities::OrganizationEntity do
  let(:names) do
    [Ammitto::Ontology::ValueObjects::NameVariant.new(full_name: 'Alias Corp', is_primary: false),
     Ammitto::Ontology::ValueObjects::NameVariant.new(full_name: 'Acme Corp', is_primary: true)]
  end

  describe '#primary_name' do
    it 'returns the primary variant full name as a String' do
      org = described_class.new(names: names)
      expect(org.primary_name).to eq('Acme Corp')
    end

    it 'falls back to the first name when none is primary' do
      org = described_class.new(names: [names.first])
      expect(org.primary_name).to eq('Alias Corp')
    end
  end

  describe '#all_names' do
    it 'lists every variant full name' do
      expect(described_class.new(names: names).all_names).to contain_exactly('Alias Corp', 'Acme Corp')
    end
  end

  describe '#primary_address' do
    it 'returns the first address when present' do
      address = Ammitto::Ontology::ValueObjects::Address.new(city: 'Bern')
      expect(described_class.new(addresses: [address]).primary_address).to eq(address)
      expect(described_class.new.primary_address).to be_nil
    end
  end

  it 'is an organization by construction' do
    expect(described_class.new).to be_organization
  end
end
