# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Ca::Record do
  # Two records transcribed from Canada's live sema-lmes.xml on
  # 2026-08-27, element names included. The first is a person; the second
  # is one of the records whose only name is the entity element.
  #
  # Transcribed rather than paraphrased on purpose: the previous version
  # of this fixture used <Country>, <LastName> and the rest, which is what
  # the file said until 24 August 2026. Canada renamed every element to a
  # bilingual form on the 25th, and because this fixture agreed with the
  # binding rather than with the source, all six examples here stayed
  # green while every live record parsed to nil.
  #
  # The item number and listing date on the second record were wrong in
  # the first draft of this fix, carried over from the old fixture rather
  # than re-read. Copy from the file; do not adapt what is already here.
  let(:xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <data-set>
        <record>
          <Country-Pays>Belarus / Bélarus</Country-Pays>
          <LastName-NomDeFamille>Atabekov</LastName-NomDeFamille>
          <GivenName-Prenom>Khazalbek Bakhtibekovich</GivenName-Prenom>
          <Schedule-Annexe>1, Part 1</Schedule-Annexe>
          <Item-NumeroDarticle>1</Item-NumeroDarticle>
          <DateOfListing-DateDinscription>2020-09-28</DateOfListing-DateDinscription>
        </record>
        <record>
          <Country-Pays>Belarus / Bélarus</Country-Pays>
          <EntityOrShip-EntiteOuNavire>Belaeronavigatsia Republican Unitary Air Navigation Services Enterprise</EntityOrShip-EntiteOuNavire>
          <Schedule-Annexe>1, Part 2</Schedule-Annexe>
          <Item-NumeroDarticle>1</Item-NumeroDarticle>
          <DateOfListing-DateDinscription>2021-06-17</DateOfListing-DateDinscription>
        </record>
      </data-set>
    XML
  end

  let(:records) do
    Ammitto::Sources::Ca::SanctionsList.from_xml(xml).records
  end

  let(:person) { records[0] }
  let(:organization) { records[1] }

  describe 'the element names Canada replaced' do
    # Nothing about the rename failed loudly: <data-set> and <record> kept
    # their names, so the document still parsed into the right number of
    # Records and every field in every one of them was nil. This pins that
    # shape, so the next rename is recognisable rather than novel.
    let(:pre_rename_xml) do
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
        </data-set>
      XML
    end

    it 'still yields one record, and that record carries nothing' do
      records =
        Ammitto::Sources::Ca::SanctionsList.from_xml(pre_rename_xml).records

      expect(records.length).to eq(1)
      expect(records.first.full_name).to eq('')
      expect(records.first.generate_id).to eq('')
    end
  end

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
