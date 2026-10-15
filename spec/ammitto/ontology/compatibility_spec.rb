# frozen_string_literal: true

require 'spec_helper'
require 'date'

# Lossless conversion between every canonical class and its legacy flat
# facade. Every field of every object in the graph carries its own sentinel,
# so a dropped, swapped or truncated field changes the result.
RSpec.describe Ammitto::Ontology::Compatibility do
  let(:contracts) { Ammitto::Ontology::Contracts }

  def snapshot(value, flags: true)
    described_class.snapshot(value, flags: flags)
  end

  Ammitto::Ontology::Contracts.registry.each_value do |concept|
    describe concept.key.to_s do
      it 'converts a complete legacy graph to the canonical classes and back without losing a field' do
        flat = CompatibilitySentinels.build(concept.legacy_class)
        canonical = described_class.canonical(flat)

        expect(canonical).to be_a(concept.canonical_class)
        expect(snapshot(canonical, flags: false)).to eq(snapshot(flat, flags: false))
        back = described_class.legacy(canonical)
        expect(back).to be_a(concept.legacy_class)
        expect(snapshot(back)).to eq(snapshot(flat))
        expect(back.to_json).to eq(flat.to_json)
        expect(back.to_yaml).to eq(flat.to_yaml)
      end

      it 'converts a complete canonical graph to the legacy facade and back without losing a field' do
        canonical = CompatibilitySentinels.build(concept.canonical_class)
        flat = described_class.legacy(canonical)

        expect(flat).to be_a(concept.legacy_class)
        expect(snapshot(flat, flags: false)).to eq(snapshot(canonical, flags: false))
        back = described_class.canonical(flat)
        expect(snapshot(back)).to eq(snapshot(canonical))
        expect(back.to_json).to eq(canonical.to_json)
        expect(back.to_yaml).to eq(canonical.to_yaml)
      end

      it 'serializes every canonical field: a JSON and a YAML round trip lose nothing' do
        canonical = CompatibilitySentinels.build(concept.canonical_class)
        from_json = concept.canonical_class.from_json(canonical.to_json)
        from_yaml = concept.canonical_class.from_yaml(canonical.to_yaml)

        expect(snapshot(from_json, flags: false)).to eq(snapshot(canonical, flags: false))
        expect(snapshot(from_yaml, flags: false)).to eq(snapshot(canonical, flags: false))
      end
    end
  end

  describe 'field correspondence (independent of the contract table)' do
    {
      Ammitto::Tonnage => [{ gross_tonnage: 1, deadweight_tonnage: 2, net_tonnage: 3, gross_register_tonnage: 4 },
                           { gt: 1, dwt: 2, nt: 3, grt: 4 }],
      Ammitto::EntityLink => [{ relationship: 'owned_by' }, { relationship_type: 'owned_by' }],
      Ammitto::SourceReference => [{ retrieved_at: '2024-01-15T10:30:00Z' }, { fetched_at: '2024-01-15T10:30:00Z' }],
      Ammitto::TemporalPeriod => [{ last_updated: '2026-10-14T13:24:55+05:00', last_updated_date: Date.new(2026, 10, 1) },
                                  { last_updated_timestamp: '2026-10-14T13:24:55+05:00',
                                    last_updated: Date.new(2026, 10, 1) }],
      Ammitto::StatusChange => [{ date: '2025-05-14T09:30:00+08:00', change_date: Date.new(2025, 5, 14) },
                                { timestamp: '2025-05-14T09:30:00+08:00', date: Date.new(2025, 5, 14) }],
      Ammitto::VesselEntity => [{ mmsi: '273', deadweight_tonnage: 7, registered_owner_name: 'Owner Ltd' },
                                { mmsi_number: '273', deadweight: 7, registered_owner: 'Owner Ltd' }],
      Ammitto::AircraftEntity => [{ registration_number: 'RA-1', flag_state: 'RU', operator_name: 'Air' },
                                  { registration: 'RA-1', registration_country: 'RU', operator: 'Air' }],
      Ammitto::SanctionEntry => [{ list_type_code: 'sdn', reason_texts: ['r'], announcement_text: 'a',
                                   raw_source_hash: { 'k' => 'v' } },
                                 { list_type: 'sdn', reasons: ['r'], announcement: 'a',
                                   raw_source_data: { 'k' => 'v' } }]
    }.each do |flat_class, (flat_fields, canonical_fields)|
      it "maps #{flat_class.name.split('::').last} #{flat_fields.keys.join(', ')}" do
        canonical = described_class.canonical(flat_class.new(**flat_fields))
        canonical_fields.each do |name, expected|
          expect(canonical.public_send(name)).to eq(expected), "canonical #{name}"
        end
      end
    end
  end

  describe 'raw source values' do
    it 'keeps a timestamp with its time and zone on the canonical side and in its JSON' do
      period = described_class.canonical(Ammitto::TemporalPeriod.new(last_updated: '2026-10-14T13:24:55+05:00',
                                                                     listed_time: '10:00+08:00',
                                                                     effective_time: '00:00'))
      expect(period.last_updated_timestamp).to eq('2026-10-14T13:24:55+05:00')
      expect(period.listed_time).to eq('10:00+08:00')
      expect(period.last_updated).to be_nil
      expect(JSON.parse(period.to_json)).to include('last_updated_timestamp' => '2026-10-14T13:24:55+05:00')
    end

    it 'keeps every LocalizedString detail, never casting the collection to text' do
      description = Ammitto::Ontology::ValueObjects::LocalizedString.new(
        value: 'Mitsubishi', language: 'en', script: 'Latn', region: 'JP', is_primary: false,
        is_transliteration: true, transliteration_system: 'hepburn'
      )
      flat = Ammitto::SanctionReason.new(category: 'other', description: [description])
      canonical = described_class.canonical(flat)

      expect(canonical.description).to be_nil
      expect(snapshot(canonical.localized_descriptions)).to eq(snapshot([description]))
      expect(canonical.localized_descriptions.first).not_to equal(description)
    end

    it 'keeps raw source content and source-specific fields' do
      raw = Ammitto::RawSourceData.new(source_format: 'xml', raw_content: '<INDIVIDUAL a="1"/>',
                                       source_specific_fields: { 'un:dataId' => '6908555' })
      canonical = described_class.canonical(Ammitto::SanctionEntry.new(raw_source_data: raw)).raw_source_detail

      expect(canonical).to be_a(Ammitto::Ontology::ValueObjects::RawSourceData)
      expect(canonical.raw_content).to eq('<INDIVIDUAL a="1"/>')
      expect(canonical.source_specific_fields).to eq('un:dataId' => '6908555')
    end
  end

  describe 'missing, explicit nil and false' do
    [
      [Ammitto::NameVariant, :is_primary], [Ammitto::BirthInfo, :circa],
      [Ammitto::TemporalPeriod, :is_indefinite], [Ammitto::SanctionEntry, :status],
      [Ammitto::Ontology::ValueObjects::NameVariant, :is_primary],
      [Ammitto::Ontology::Sanction::SanctionEntry, :status]
    ].each do |klass, field|
      { 'missing' => {}, 'explicit nil' => { field => nil }, 'false' => { field => false } }.each do |label, input|
        it "#{klass.name.split('::').last}##{field} #{label} survives both directions with its default flag" do
          source = klass.new(**input)
          other = Ammitto::Ontology::Contracts.lookup(klass).last == :legacy ? :canonical : :legacy
          there = described_class.public_send(other, source)
          back = described_class.public_send(other == :legacy ? :canonical : :legacy, there)

          expect(there.using_default?(field)).to eq(source.using_default?(field))
          expect(snapshot(back)).to eq(snapshot(source))
          expect(back.to_json).to eq(source.to_json)
        end
      end
    end

    it 'keeps NameVariant is_strong true, false and nil through canonical JSON, YAML, to_hash and Neo4j' do
      klass = Ammitto::Ontology::ValueObjects::NameVariant
      [true, false].each do |strong|
        name = klass.new(full_name: 'N', is_strong: strong)
        expect(klass.from_json(name.to_json).is_strong).to eq(strong)
        expect(klass.from_yaml(name.to_yaml).is_strong).to eq(strong)
        expect(name.to_hash).to include(is_strong: strong)
        expect(name.to_neo4j_properties).to include(is_strong: strong)
        expect(described_class.legacy(name).is_strong).to eq(strong)
      end
      expect(klass.new(full_name: 'N').to_hash).not_to have_key(:is_strong)
    end

    it 'keeps an explicitly set entity_type explicit, and a defaulted one defaulted' do
      explicit = Ammitto::PersonEntity.new(entity_type: 'person')
      defaulted = Ammitto::PersonEntity.new

      expect(described_class.legacy(described_class.canonical(explicit)).to_json).to eq(explicit.to_json)
      expect(described_class.legacy(described_class.canonical(defaulted)).to_json).to eq(defaulted.to_json)
      expect(explicit.to_json).not_to eq(defaulted.to_json)
    end
  end

  describe 'ownership' do
    it 'copies strings and collections instead of sharing them, and leaves the source untouched' do
      flat = Ammitto::PersonEntity.new(names: [Ammitto::NameVariant.new(full_name: 'Ivan'.dup)], same_as: ['x'.dup])
      before = snapshot(flat)
      canonical = described_class.canonical(flat)

      expect(snapshot(flat)).to eq(before)
      expect(flat).not_to be_frozen
      expect(canonical.names.first.full_name).not_to equal(flat.names.first.full_name)
      expect(canonical.same_as).not_to equal(flat.same_as)

      flat.names.first.full_name << ' changed'
      flat.same_as << 'y'
      expect(canonical.names.first.full_name).to eq('Ivan')
      expect(canonical.same_as).to eq(['x'])
    end

    it 'carries sanction entries and the search authority of an entity' do
      entry = Ammitto::SanctionEntry.new(id: 'https://www.ammitto.org/entry/eu/x/1', status: 'active')
      flat = Ammitto::PersonEntity.new(id: 'https://www.ammitto.org/entity/eu/1')
      flat.add_sanction_entry(entry)
      flat.explicit_authority = 'un'
      canonical = described_class.canonical(flat)
      back = described_class.legacy(canonical)

      expect(canonical.sanction_entries.map(&:class)).to eq([Ammitto::Ontology::Sanction::SanctionEntry])
      expect(canonical.sanction_entry_ids).to eq(['https://www.ammitto.org/entry/eu/x/1'])
      expect(back.sanction_entries.map(&:id)).to eq(['https://www.ammitto.org/entry/eu/x/1'])
      expect(back.authority).to eq('un')
    end
  end

  describe 'conflicts' do
    it 'refuses to round a fractional canonical vessel length into the Integer legacy field' do
      expect { described_class.legacy(Ammitto::Ontology::Entities::VesselEntity.new(length: 12.5)) }
        .to raise_error(described_class::ConflictError, /length/)
      expect(described_class.legacy(Ammitto::Ontology::Entities::VesselEntity.new(length: 12.0)).length).to eq(12)
    end

    it 'refuses a legacy entity_type the canonical subclass would overwrite' do
      expect { described_class.canonical(Ammitto::PersonEntity.new(entity_type: 'organization')) }
        .to raise_error(described_class::ConflictError, /entity_type/)
    end

    it 'refuses a value the target initializer would derive, not only values it would drop' do
      # canonical StatusHistory#initialize fills to_status from status
      expect { described_class.canonical(Ammitto::StatusChange.new(status: 'suspended')) }
        .to raise_error(described_class::ConflictError, /to_status/)
      both = Ammitto::StatusChange.new(status: 'suspended', to_status: 'suspended')
      expect(snapshot(described_class.legacy(described_class.canonical(both)))).to eq(snapshot(both))
    end

    it 'refuses a model with no contract instead of passing it through unconverted' do
      expect { described_class.canonical(Ammitto::Sources::Eu::Address.new) }
        .to raise_error(described_class::ConflictError, /no canonical/)
      expect { described_class.canonical(Class.new(Ammitto::PersonEntity).new) }
        .to raise_error(described_class::ConflictError, /no contract of its own/)
    end

    it 'is an Ammitto::Error like every other gem error' do
      expect(described_class::ConflictError.ancestors).to include(Ammitto::Error)
    end
  end
end
