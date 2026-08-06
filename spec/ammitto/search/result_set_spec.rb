# frozen_string_literal: true

require 'ammitto'

RSpec.describe Ammitto::Search::ResultSet do
  let(:entity_iri) { 'https://www.ammitto.org/entity/eu/eu1' }
  let(:entry_iri) { 'https://www.ammitto.org/entry/eu/consolidated-list/eu1' }

  def result_set(node)
    described_class.new([node])
  end

  describe 'building models from a JSON-LD node' do
    it 'keeps the entity->entry edge the producer emits as hasSanctionEntry' do
      set = result_set(
        '@id' => entity_iri,
        '@type' => 'PersonEntity',
        'entityType' => 'person',
        'hasSanctionEntry' => [entry_iri]
      )

      expect(set.first.sanction_entry_ids).to eq([entry_iri])
    end

    it 'accepts node references as well as IRI strings' do
      set = result_set(
        '@id' => entity_iri,
        'entityType' => 'person',
        'hasSanctionEntry' => [{ '@id' => entry_iri }]
      )

      expect(set.first.sanction_entry_ids).to eq([entry_iri])
    end

    it 'still reads the legacy snake_case spelling' do
      set = result_set(
        'id' => entity_iri,
        'entity_type' => 'person',
        'sanction_entry_ids' => [entry_iri]
      )

      expect(set.first.sanction_entry_ids).to eq([entry_iri])
    end

    it 'accepts a lone node reference that is not wrapped in an array' do
      set = result_set(
        '@id' => entity_iri,
        'entityType' => 'person',
        'hasSanctionEntry' => { '@id' => entry_iri }
      )

      expect(set.first.sanction_entry_ids).to eq([entry_iri])
    end

    it 'accepts a symbol-keyed Ruby hash reference' do
      set = result_set(
        '@id' => entity_iri,
        'entityType' => 'person',
        'hasSanctionEntry' => [{ '@id': entry_iri }]
      )

      expect(set.first.sanction_entry_ids).to eq([entry_iri])
    end

    it 'trims and deduplicates padded variants of one reference' do
      set = result_set(
        '@id' => entity_iri,
        'entityType' => 'person',
        'hasSanctionEntry' => [" #{entry_iri} ", entry_iri]
      )

      expect(set.first.sanction_entry_ids).to eq([entry_iri])
    end

    it 'does not let a blank @id mask a usable id on the same reference' do
      set = result_set(
        '@id' => entity_iri,
        'entityType' => 'person',
        'hasSanctionEntry' => [{ '@id' => '  ', 'id' => entry_iri }]
      )

      expect(set.first.sanction_entry_ids).to eq([entry_iri])
    end

    it 'prefers the canonical wire key in every permutation of the three spellings' do
      values = {
        'sanction_entry_ids' => ['https://www.ammitto.org/entry/eu/l/snake'],
        'sanctionEntries' => ['https://www.ammitto.org/entry/eu/l/alias'],
        'hasSanctionEntry' => [entry_iri]
      }

      values.keys.permutation do |order|
        node = { '@id' => entity_iri, 'entityType' => 'person' }
        order.each { |k| node[k] = values[k] }

        expect(result_set(node).first.sanction_entry_ids)
          .to eq([entry_iri]), "order #{order.inspect} lost the canonical value"
      end
    end

    it 'drops blank references rather than carrying empty IRIs' do
      set = result_set(
        '@id' => entity_iri,
        'entityType' => 'person',
        'hasSanctionEntry' => ['', '  ', nil, { 'nope' => 1 }, entry_iri]
      )

      expect(set.first.sanction_entry_ids).to eq([entry_iri])
    end
  end

  describe '#to_json_ld' do
    it 'round-trips the edge back onto the serialized entity' do
      set = result_set(
        '@id' => entity_iri,
        '@type' => 'PersonEntity',
        'entityType' => 'person',
        'hasSanctionEntry' => [entry_iri]
      )

      node = set.to_json_ld['@graph'].find { |n| n['@id'] == entity_iri }

      expect(node['hasSanctionEntry']).to eq([entry_iri])
    end
  end
end
