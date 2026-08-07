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

  # A result set holds whatever the search returned, and the class is
  # built for two kinds of member: #build_from_hash routes a node typed
  # "SanctionEntry" to SanctionEntry and everything else to an Entity, and
  # #to_json_ld greps the set for both classes separately. The two
  # families carry different attributes — SanctionEntry has authority and
  # status and no entity_type, Entity has entity_type and neither of the
  # others — so every filter on this class meets members that cannot
  # answer it.
  #
  # #by_authority and #by_status were written for that and skip a member
  # that cannot answer. #entity_types and #by_entity_type were not, and
  # raised NoMethodError on any set holding one entry, taking down the
  # types of every entity in the set with it.
  def person
    Ammitto::PersonEntity.new(id: 'https://www.ammitto.org/entity/tr/1',
                              entity_type: 'person')
  end

  def organization
    Ammitto::OrganizationEntity.new(
      id: 'https://www.ammitto.org/entity/tr/2', entity_type: 'organization'
    )
  end

  # Exactly what JsonLdSerializer#serialize_entry writes for an entry with
  # no matching entity: an id, the entity it points at, and a status.
  def entry
    Ammitto::SanctionEntry.new(id: 'https://www.ammitto.org/entry/tr/1',
                               entity_id: 'https://www.ammitto.org/entity/tr/1',
                               status: 'active')
  end

  def mixed
    described_class.new([person, organization, entry], term: 'acme')
  end

  def entities_only
    described_class.new([person, organization], term: 'acme')
  end

  describe '#entity_types' do
    it 'reports the types of a set that also holds an entry' do
      expect(mixed.entity_types).to eq(%w[person organization])
    end

    it 'reports the same types with the entry present as without it' do
      # The entry contributes nothing, which is the claim — not that the
      # call merely survives.
      expect(mixed.entity_types).to eq(entities_only.entity_types)
    end

    it 'reports nothing for a set holding only entries' do
      expect(described_class.new([entry], term: 'acme').entity_types).to eq([])
    end
  end

  describe '#by_entity_type' do
    it 'filters a set that also holds an entry' do
      expect(mixed.by_entity_type(:person).to_a).to eq([person])
    end

    it 'selects the same members with the entry present as without it' do
      expect(mixed.by_entity_type('organization').to_a)
        .to eq(entities_only.by_entity_type('organization').to_a)
    end

    it 'never admits an entry as an entity of any type' do
      # An entry has no entity_type, so no argument may match it. Asking
      # for each type the set reports, plus the type of the entity the
      # entry belongs to, must never return the entry itself.
      matched = (mixed.entity_types + ['person']).flat_map do |type|
        mixed.by_entity_type(type).to_a
      end

      expect(matched).to all(be_a(Ammitto::Entity))
    end
  end

  # The guard is the siblings' guard, so the four filters answer the one
  # set alike. Stated as one example because the defect was precisely
  # that two of the four behaved differently from the other two.
  describe 'the filters that meet members which cannot answer them' do
    it 'answers every filter on one mixed set' do
      set = mixed

      expect({ entity_types: set.entity_types,
               authorities: set.authorities,
               person: set.by_entity_type(:person).to_a,
               authority: set.by_authority(:tr).to_a,
               status: set.by_status(:active).to_a })
        .to eq(entity_types: %w[person organization],
               authorities: [],
               person: [person],
               authority: [],
               status: [entry])
    end
  end

  # Reachable through the documented public entry point, not only through
  # the constructor: Ammitto.search builds a result set out of whatever
  # graph nodes matched, and BaseSource#search matches any node carrying
  # the name — including one typed SanctionEntry.
  describe 'a search whose matches include an entry node' do
    def result_set_for(graph)
      described_class.new(graph.map { |node| node })
    end

    it 'reports the entity types among the matched nodes' do
      graph = [
        { '@id' => 'https://www.ammitto.org/entity/tr/1',
          '@type' => 'PersonEntity', 'entityType' => 'person',
          'names' => [{ 'fullName' => 'ACME' }] },
        { '@id' => 'https://www.ammitto.org/entry/tr/1',
          '@type' => 'SanctionEntry', 'status' => 'active',
          'names' => [{ 'fullName' => 'ACME' }] }
      ]
      results = result_set_for(graph)

      expect(results.to_a.map(&:class))
        .to eq([Ammitto::PersonEntity, Ammitto::SanctionEntry])
      expect(results.entity_types).to eq(['person'])
    end
  end
end
