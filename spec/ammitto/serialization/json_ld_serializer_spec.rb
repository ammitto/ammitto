# frozen_string_literal: true

require 'ammitto'
require 'json/ld'

RSpec.describe Ammitto::Serialization::JsonLdSerializer do
  subject(:serializer) { described_class.new }

  let(:entry_iri) { 'https://www.ammitto.org/entry/cn/unreliable-entity-list/acme' }
  let(:entity_iri) { 'https://www.ammitto.org/entity/cn/acme' }

  def build_entity(**overrides)
    Ammitto::PersonEntity.new(
      {
        id: entity_iri,
        entity_type: 'person',
        names: [Ammitto::NameVariant.new(full_name: 'ACME Person', is_primary: true)]
      }.merge(overrides)
    )
  end

  def build_entry(**overrides)
    Ammitto::SanctionEntry.new({ id: entry_iri, entity_id: entity_iri }.merge(overrides))
  end

  describe '#serialize_entity' do
    context 'with the entity->entry edge' do
      it 'emits hasSanctionEntry as the IRI strings the context declares' do
        entity = build_entity(sanction_entry_ids: [entry_iri])

        expect(serializer.serialize_entity(entity)['hasSanctionEntry'])
          .to eq([entry_iri])
      end

      it 'deduplicates repeated entry IRIs' do
        entity = build_entity(sanction_entry_ids: [entry_iri, entry_iri])

        expect(serializer.serialize_entity(entity)['hasSanctionEntry'])
          .to eq([entry_iri])
      end

      it 'omits the key when the entity carries no entries' do
        expect(serializer.serialize_entity(build_entity)).not_to have_key('hasSanctionEntry')
      end

      it 'omits the key rather than emitting blank IRIs' do
        entity = build_entity(sanction_entry_ids: ['', '  '])

        expect(serializer.serialize_entity(entity)).not_to have_key('hasSanctionEntry')
      end

      it 'trims before deduplicating so padded variants are one reference' do
        entity = build_entity(sanction_entry_ids: [" #{entry_iri} ", entry_iri])

        expect(serializer.serialize_entity(entity)['hasSanctionEntry']).to eq([entry_iri])
      end
    end
  end

  describe '#serialize_entry' do
    it 'emits modification nodes with their source and affected entry references' do
      modification = Ammitto::Ontology::Sanction::SanctionPeriodModification.new(
        id: 'https://www.ammitto.org/modification/cn/20250514-20257',
        target_type: 'announcement',
        target_id: [entry_iri],
        target_announcement_id: 'https://www.ammitto.org/announcement/cn/20257',
        target_announcement_document_id: '〔2025〕7号',
        action: 'suspend',
        effective_date: Date.new(2025, 5, 14),
        until_date: Date.new(2025, 8, 12),
        announcement: { 'id' => 'https://www.ammitto.org/announcement/cn/202505142200' },
        affected_entity_count: 1,
        notes: '暂停相关措施90天'
      )

      node = serializer.serialize_entry(build_entry(modifications: [modification]))
      mod = node['modifications'].first

      expect(mod).to include(
        '@id' => modification.id,
        '@type' => 'SanctionPeriodModification',
        'targetType' => 'announcement',
        'targetId' => [entry_iri],
        'targetAnnouncementId' => 'https://www.ammitto.org/announcement/cn/20257',
        'targetAnnouncementDocumentId' => '〔2025〕7号',
        'effectiveDate' => Date.new(2025, 5, 14),
        'untilDate' => Date.new(2025, 8, 12),
        'affectedEntityCount' => 1,
        'notes' => '暂停相关措施90天'
      )
      expect(mod['announcement']).to include(
        '@type' => 'OfficialAnnouncement',
        '@id' => 'https://www.ammitto.org/announcement/cn/202505142200'
      )
      expect(mod).not_to have_key('status')
    end

    it 'emits groupId' do
      group_iri = 'https://www.ammitto.org/group/cn/2026-1'
      entry = build_entry(group_id: group_iri)

      expect(serializer.serialize_entry(entry)['groupId']).to eq(group_iri)
    end

    it 'omits groupId when the entry belongs to no group' do
      expect(serializer.serialize_entry(build_entry)).not_to have_key('groupId')
    end

    context 'with legal citations' do
      let(:instrument_iri) { 'https://www.ammitto.org/legal_instrument/cn/afsl' }
      let(:citation) do
        Ammitto::Ontology::ValueObjects::LegalCitation.new(
          legal_instrument_id: instrument_iri,
          articles: ['Article 4'],
          citation_type: 'legal_basis'
        )
      end

      it 'emits the camelCase term names the context declares' do
        entry = build_entry(legal_citations: [citation])

        expect(serializer.serialize_entry(entry)['legalCitations']).to eq(
          [{
            '@type' => 'LegalCitation',
            'legalInstrumentId' => instrument_iri,
            'articles' => ['Article 4'],
            'citationType' => 'legal_basis'
          }]
        )
      end

      it 'emits every field the context declares for a citation' do
        full = Ammitto::Ontology::ValueObjects::LegalCitation.new(
          id: 'https://www.ammitto.org/citation/cn/1',
          legal_instrument_id: instrument_iri,
          articles: ['Article 4'],
          sections: ['Section 2'],
          paragraphs: ['Paragraph 1'],
          citation_type: 'legal_basis',
          context: 'Primary authority',
          quoted_text: [
            Ammitto::Ontology::ValueObjects::LocalizedString.new(value: 'quoted', language: 'en')
          ]
        )
        entry = build_entry(legal_citations: [full])

        expect(serializer.serialize_entry(entry)['legalCitations'].first.keys).to contain_exactly(
          '@id', '@type', 'legalInstrumentId', 'articles', 'sections',
          'paragraphs', 'citationType', 'context', 'quotedText'
        )
      end

      it 'keeps a citation that carries only quoted text' do
        quoted = Ammitto::Ontology::ValueObjects::LegalCitation.new(
          quoted_text: [
            Ammitto::Ontology::ValueObjects::LocalizedString.new(value: 'quoted', language: 'en')
          ]
        )
        entry = build_entry(legal_citations: [quoted])

        expect(serializer.serialize_entry(entry)['legalCitations'].first['quotedText'])
          .to eq([{ '@type' => 'LocalizedString', 'value' => 'quoted', 'lang' => 'en',
                    'isPrimary' => false, 'isTransliteration' => false }])
      end

      it 'omits empty collection attributes rather than emitting empty arrays' do
        entry = build_entry(
          legal_citations: [
            Ammitto::Ontology::ValueObjects::LegalCitation.new(legal_instrument_id: instrument_iri)
          ]
        )

        expect(serializer.serialize_entry(entry)['legalCitations'].first.keys)
          .to contain_exactly('@type', 'legalInstrumentId')
      end

      it 'omits the key when the entry carries no citations' do
        expect(serializer.serialize_entry(build_entry)).not_to have_key('legalCitations')
      end
    end
  end

  # A field that is not serialized is a field the website never sees,
  # however faithfully the models carry it.
  describe 'an announcement embedded in a modification as a hash' do
    it 'keeps every field whether keyed by JSON-LD term or attribute name, string or symbol' do
      built = { id: 'a', publish_date: '2025-11-05', authority: 'MOFCOM', content: 'C' }
      parsed = { '@id' => 'a', 'publishDate' => '2025-11-05', 'authority' => 'MOFCOM', 'content' => 'C' }

      expect(serializer.send(:serialize_embedded_announcement, built))
        .to eq(serializer.send(:serialize_embedded_announcement, parsed))
        .and include('@id' => 'a', 'publishDate' => '2025-11-05', 'authority' => 'MOFCOM', 'content' => 'C')
    end
  end

  describe 'birth date and year ranges' do
    def birth_node(**attrs)
      entity = build_entity(birth_info: [Ammitto::BirthInfo.new(**attrs)])
      serializer.serialize_entity(entity)['birthInfo'].first
    end

    it 'emits both bounds under the camelCase contract names' do
      node = birth_node(year_range_from: 1953, year_range_to: 1958)

      expect(node['yearRangeFrom']).to eq(1953)
      expect(node['yearRangeTo']).to eq(1958)
    end

    it 'emits only the bound that exists, leaving the span open' do
      node = birth_node(year_range_to: 1980)

      expect(node['yearRangeTo']).to eq(1980)
      expect(node).not_to have_key('yearRangeFrom')
    end

    it 'emits no year alongside a span' do
      expect(birth_node(year_range_from: 1953, year_range_to: 1958))
        .not_to have_key('year')
    end

    it 'keeps circa independent of the span' do
      expect(birth_node(year_range_from: 1953, year_range_to: 1958, circa: true)['circa'])
        .to be true
    end

    # An exact-year record must come out the shape it always did, so a
    # consumer reading today's artifacts sees no change at all.
    it 'leaves an exact-year record byte-identical apart from ordering' do
      expect(birth_node(year: 1964, city: 'Bern').sort.to_h)
        .to eq({ '@type' => 'BirthInfo', 'circa' => false,
                 'year' => 1964, 'city' => 'Bern' }.sort.to_h)
    end

    # The node holds real Date objects, so the bounds are read after
    # generation: that is the form the website actually receives.
    it 'emits complete date bounds under the camelCase contract names' do
      node = JSON.parse(JSON.generate(birth_node(
                                        date_range_from: Date.new(1961, 1, 1),
                                        date_range_to: Date.new(1962, 12, 31)
                                      )))

      expect(node['dateRangeFrom']).to eq('1961-01-01')
      expect(node['dateRangeTo']).to eq('1962-12-31')
    end

    it 'emits only the date bound that exists' do
      node = JSON.parse(JSON.generate(birth_node(
                                        date_range_to: Date.new(1962, 12, 31)
                                      )))

      expect(node['dateRangeTo']).to eq('1962-12-31')
      expect(node).not_to have_key('dateRangeFrom')
    end

    # A same-year span is the one shape that carries date bounds AND a
    # scalar year at once, and the scalar is the fragile half: 'year' is
    # suppressed beside a YEAR span two examples above, so a serializer
    # that generalised that suppression to date bounds would strip the
    # exact year off every same-year OFAC span and take birthYear out of
    # the search index with it. The transformer's half of this is pinned
    # in base_transformer_spec; this pins that the value survives being
    # serialized, which is the only form the website ever sees.
    it 'keeps the exact year of a same-year span beside its date bounds' do
      node = JSON.parse(JSON.generate(birth_node(
                                        year: 1962,
                                        date_range_from: Date.new(1962, 1, 1),
                                        date_range_to: Date.new(1962, 12, 31),
                                        year_range_from: 1962,
                                        year_range_to: 1962
                                      )))

      expect(node['year']).to eq(1962)
      expect(node['dateRangeFrom']).to eq('1962-01-01')
      expect(node['dateRangeTo']).to eq('1962-12-31')
      expect(node['yearRangeFrom']).to eq(1962)
      expect(node['yearRangeTo']).to eq(1962)
    end
  end

  describe 'the generated JSON-LD context' do
    let(:terms) { Ammitto::Schema::Context.context['@context'] }

    it 'declares the raw CN target announcement document number' do
      expect(terms['targetAnnouncementDocumentId']).to eq(
        '@id' => 'targetAnnouncementDocumentId'
      )
    end

    it 'declares both bounds as gYear, so a consumer can type them' do
      expect(terms['yearRangeFrom'])
        .to eq({ '@id' => 'yearRangeFrom', '@type' => 'xsd:gYear' })
      expect(terms['yearRangeTo'])
        .to eq({ '@id' => 'yearRangeTo', '@type' => 'xsd:gYear' })
    end

    # The serializer has always emitted 'year' inside a BirthInfo node,
    # and the pre-existing 'birthYear' term describes the flat
    # entity-level key, not this one.
    it 'declares the year key the serializer actually emits' do
      expect(terms['year']).to eq({ '@id' => 'year', '@type' => 'xsd:gYear' })
    end

    it 'keeps the existing birthYear term untouched' do
      expect(terms['birthYear'])
        .to eq({ '@id' => 'birthYear', '@type' => 'xsd:gYear' })
    end

    # Two configuration hashes agreeing proves only that two hashes
    # agree. This expands a real birth node against the real context and
    # reads the datatype off the resulting literals, which is what a
    # consumer actually gets.
    it 'expands the year keys to gYear literals, not bare numbers' do
      node = serializer.serialize_entity(
        build_entity(birth_info: [Ammitto::BirthInfo.new(
          year_range_from: 1953, year_range_to: 1958
        )])
      ).merge(Ammitto::Schema::Context.context)

      vocab = 'https://ammitto.org/schema/v1/'
      birth = JSON::LD::API.expand(node).first["#{vocab}birthInfo"].first

      %w[yearRangeFrom yearRangeTo].each do |term|
        literal = birth["#{vocab}#{term}"].first
        expect(literal['@type'])
          .to eq('http://www.w3.org/2001/XMLSchema#gYear')
      end
    end

    it 'declares both date bounds as xsd:date' do
      expect(terms['dateRangeFrom'])
        .to eq({ '@id' => 'dateRangeFrom', '@type' => 'xsd:date' })
      expect(terms['dateRangeTo'])
        .to eq({ '@id' => 'dateRangeTo', '@type' => 'xsd:date' })
    end

    it 'expands the date bounds to xsd:date literals' do
      node = serializer.serialize_entity(
        build_entity(birth_info: [Ammitto::BirthInfo.new(
          date_range_from: Date.new(1961, 1, 1),
          date_range_to: Date.new(1962, 12, 31)
        )])
      ).merge(Ammitto::Schema::Context.context)
      node = JSON.parse(JSON.generate(node))

      vocab = 'https://ammitto.org/schema/v1/'
      birth = JSON::LD::API.expand(node).first["#{vocab}birthInfo"].first

      %w[dateRangeFrom dateRangeTo].each do |term|
        literal = birth["#{vocab}#{term}"].first
        expect(literal['@type'])
          .to eq('http://www.w3.org/2001/XMLSchema#date')
      end
    end
  end

  describe '#serialize_document' do
    let(:document) { serializer.serialize_document(entities: [build_entity], entries: [build_entry]) }
    let(:entity_node) { document['@graph'].find { |n| n['@id'] == entity_iri } }

    it 'links the entity to its entry by IRI rather than embedding the entry' do
      expect(entity_node['hasSanctionEntry']).to eq([entry_iri])
    end

    it 'keeps every entry as a node of its own so the reference resolves' do
      expect(document['@graph'].map { |n| n['@id'] }).to contain_exactly(entity_iri, entry_iri)
    end

    it 'emits a set even for a single entry' do
      expect(entity_node['hasSanctionEntry']).to be_an(Array)
    end
  end
end
