# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Ca::Record do
  # Two records copied from Canada's sema-lmes.xml. The first is a
  # person; the second is one of the 2175 records (of 5684) whose only
  # name is <EntityOrShip>.
  let(:xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <data-set>
        <record>
          <Country>Belarus</Country>
          <LastName>Atabekov</LastName>
          <GivenName>Khazalbek Bakhtibekovich</GivenName>
          <Schedule>1, Part 1</Schedule>
          <Item>1</Item>
          <DateOfListing>2020-09-28</DateOfListing>
        </record>
        <record>
          <Country>Belarus</Country>
          <EntityOrShip>Belaeronavigatsia Republican Unitary Air Navigation Services Enterprise</EntityOrShip>
          <Schedule>1, Part 2</Schedule>
          <Item>7</Item>
          <DateOfListing>2023-06-30</DateOfListing>
        </record>
      </data-set>
    XML
  end

  let(:records) do
    Ammitto::Sources::Ca::SanctionsList.from_xml(xml).records
  end

  let(:person) { records[0] }
  let(:organization) { records[1] }

  describe '#full_name' do
    it 'joins the given and last name of a person record' do
      expect(person.full_name).to eq('Khazalbek Bakhtibekovich Atabekov')
    end

    it 'names an organization from its EntityOrShip element' do
      expect(organization.full_name)
        .to eq('Belaeronavigatsia Republican Unitary Air Navigation ' \
               'Services Enterprise')
    end

    it 'leaves a record with no name at all empty' do
      bare = described_class.new(country: 'Belarus')

      expect(bare.full_name).to eq('')
    end
  end

  describe 'XML mapping' do
    it 'reads EntityOrShip into its own attribute' do
      expect(organization.entity_or_ship)
        .to eq('Belaeronavigatsia Republican Unitary Air Navigation ' \
               'Services Enterprise')
    end

    # Ca::Transformer#transform branches on #individual?, not on
    # #entity_type, so this is the predicate that decides the node class.
    it 'still routes an EntityOrShip record to the organization branch' do
      expect(organization.individual?).to be(false)
      expect(person.individual?).to be(true)
    end
  end

  describe 'YAML round trip' do
    # `fetch ca` writes each record with this mapping and `harmonize`
    # reads it back, so a name dropped here is a name the pipeline can
    # never publish.
    it 'carries EntityOrShip through processed YAML' do
      round_tripped = described_class.from_yaml(organization.to_yaml)

      expect(round_tripped.full_name).to eq(organization.full_name)
    end
  end
end
