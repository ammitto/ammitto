# frozen_string_literal: true

require 'json'
require 'ammitto'

# Nodes copied unmodified from the cached un_vessels and un sources; neither
# carries an authority field.
module EntityAuthoritySpecNodes
  def cached_nodes
    JSON.parse(File.read(File.join(__dir__, '..', 'fixtures', 'search', 'cached_entity_nodes.json')))
  end

  def cached_entry_node
    JSON.parse(File.read(File.join(__dir__, '..', 'fixtures', 'search', 'cached_entry_node.json')))
  end
end

RSpec.describe Ammitto::Entity do
  include EntityAuthoritySpecNodes

  describe '#authority' do
    it 'comes from the entity IRI segment when the node names none' do
      codes = cached_nodes.map { |node| Ammitto::Search::ResultSet.new([node]).first.authority }

      expect(codes).to eq(%w[un_vessels un])
    end

    it 'prefers an explicit @id reference' do
      node = cached_nodes.first.merge('authority' => { '@id' => 'https://www.ammitto.org/authority/eu' })

      expect(Ammitto::Search::ResultSet.new([node]).first.authority).to eq('eu')
    end

    it 'downcases the code of an explicit @id reference' do
      node = cached_nodes.first.merge('authority' => { '@id' => 'https://www.ammitto.org/authority/EU' })

      expect(Ammitto::Search::ResultSet.new([node]).first.authority).to eq('eu')
    end

    it 'prefers an explicit own id' do
      node = cached_nodes.first.merge('authority' => { 'id' => 'UK' })

      expect(Ammitto::Search::ResultSet.new([node]).first.authority).to eq('uk')
    end

    it 'accepts a bare string authority as the code' do
      node = cached_nodes.first.merge('authority' => 'EU')

      expect(Ammitto::Search::ResultSet.new([node]).first.authority).to eq('eu')
    end

    it 'tolerates a trailing slash and ignores an IRI that is not ours' do
      slash = described_class.new(id: 'urn:other:1')
      slash.explicit_authority = { '@id' => 'https://www.ammitto.org/authority/EU/' }
      foreign = described_class.new(id: 'urn:other:2')
      foreign.explicit_authority = { '@id' => 'https://example.org/authority/un' }

      expect([slash.authority, foreign.authority]).to eq(['eu', nil])
    end

    it 'is nil for an entity whose id is nil or lutaml\'s uninitialized value' do
      entity = described_class.new(entity_type: 'person')
      expect(entity.authority).to be_nil

      allow(entity).to receive(:id).and_return(Lutaml::Model::UninitializedClass.instance)
      expect(entity.authority).to be_nil
      expect(Ammitto::Search::ResultSet.new([{ 'entityType' => 'person' }]).authorities).to eq([])
    end

    it 'downcases the IRI segment' do
      entity = described_class.new(id: 'https://www.ammitto.org/entity/EU/2')

      expect(entity.authority).to eq('eu')
    end

    it 'reads the code from an entity IRI on the apex host too' do
      entity = described_class.new(id: 'https://ammitto.org/entity/eu/2')

      expect(entity.authority).to eq('eu')
    end

    it 'is nil when the IRI segment is not an authority code' do
      ['https://www.ammitto.org/entity/u n/1', 'https://www.ammitto.org/entity/un /1',
       'https://www.ammitto.org/entity/ un/1'].each do |iri|
        entity = Ammitto::PersonEntity.new(id: iri)
        expect([entity.authority, Ammitto::Search::ResultSet.new([entity]).by_authority(:un).size]).to eq([nil, 0])
      end
    end

    it 'is nil when the IRI segment is empty' do
      entity = described_class.new(id: 'https://www.ammitto.org/entity//3')

      expect(entity.authority).to be_nil
    end

    it 'is nil when the node id is not a string' do
      set = Ammitto::Search::ResultSet.new([{ '@id' => [], '@type' => 'Unknown' }])

      expect(set.authorities).to eq([])
    end

    it 'is nil when there is neither an authority nor an ammitto entity IRI' do
      expect(described_class.new(id: 'urn:other:1').authority).to be_nil
    end
  end

  describe 'authority values of any shape on a ResultSet node' do
    let(:iri) { 'https://www.ammitto.org/entity/un/1' }

    it 'takes the first usable value of the string and symbol spellings' do
      set = Ammitto::Search::ResultSet.new([{ '@id' => iri, 'authority' => nil, authority: 'EU' }])

      expect(set.first.authority).to eq('eu')
    end

    [%w[a b], 7, true, nil].each do |value|
      it "ignores #{value.inspect} and keeps the IRI-derived code" do
        set = Ammitto::Search::ResultSet.new([{ '@id' => iri, 'entityType' => 'person', 'authority' => value }])

        expect(set.authorities).to eq(['un'])
      end
    end
  end

  describe 'a set mixing cached entity and entry nodes' do
    let(:set) { Ammitto::Search::ResultSet.new([cached_nodes.last, cached_entry_node]) }

    it 'names one authority code for both' do
      expect(set.authorities).to eq(['un'])
    end

    it 'filters both by code, whatever its case' do
      expect(set.by_authority('UN').size).to eq(2)
    end
  end

  # Explicit authority is read by the search layer only; the entity's own
  # serialization is what it always was.
  describe 'serialization' do
    let(:json) do
      '{"id":"https://www.ammitto.org/entity/un/1","entityType":"person",' \
        '"names":[{"fullName":"A","isPrimary":true}]'
    end

    it 'does not carry an authority, however the entity was built' do
      node = { '@id' => 'https://www.ammitto.org/authority/eu' }
      entity = Ammitto::Search::ResultSet.new([cached_nodes.first.merge('authority' => node)]).first

      expect(entity.authority).to eq('eu')
      expect(entity.to_json).not_to include('authority')
      expect(entity.to_hash.keys).not_to include('authority')
    end

    it 'reads and writes an entity without an authority as before' do
      out = Ammitto::PersonEntity.from_json("#{json}}").to_json

      expect(out).to eq(
        '{"id":"https://www.ammitto.org/entity/un/1","entity_type":"person","entityType":"person",' \
        '"names":[{"full_name":"A","fullName":"A","is_primary":true,"isPrimary":true}]}'
      )
    end

    it 'ignores an authority key in JSON' do
      entity = Ammitto::PersonEntity.from_json(%(#{json},"authority":"EU"}))

      expect(entity.authority).to eq('un')
    end
  end
end
