# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/cn/announcement'
require 'ammitto/sources/cn/transformer'

RSpec.describe Ammitto::Sources::Cn::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :cn' do
      expect(transformer.source_code).to eq(:cn)
    end
  end

  describe '#authority' do
    it 'returns CN authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('cn')
      expect(auth.name).to eq('China (MOFCOM/MFA)')
    end
  end

  describe '#transform_announcement list identity' do
    def announcement_data(sanction_list)
      {
        'announcement' => {
          'title' => [{ 'zh-Hans' => '公告', 'en' => 'Announcement' }],
          'document_id' => 'mofcom-2026-01',
          'publish_date' => '2026-01-01'
        },
        'sanction_details' => {
          'entities' => [
            {
              'name' => { 'zh-Hans' => '测试公司', 'en' => 'Test Corp' },
              'type' => 'organization',
              'effective_date' => '2026-01-01',
              'sanction_list' => sanction_list
            }
          ]
        }
      }
    end

    def entry_for(sanction_list)
      announcement = Ammitto::Sources::Cn::Announcement
                     .from_hash(announcement_data(sanction_list))
      described_class.new.transform_announcement(announcement)[:entries].first
    end

    it 'writes the real list slug into entry IRIs for slug data' do
      entry = entry_for('cn/unreliable-entity-list')

      expect(entry.id).to include('/entry/cn/unreliable-entity-list/')
      expect(entry.id).not_to include('/unknown')
    end

    it 'writes the real regime for slug data' do
      entry = entry_for('cn/anti-sanction-list')

      expect(entry.regime.code).to eq('CN_ANTI_SANCTIONS')
    end

    it 'keeps matching Chinese label data' do
      entry = entry_for('出口管制管控名单')

      expect(entry.id).to include('/entry/cn/import-export-control-list/')
      expect(entry.regime.code).to eq('CN_EXPORT_CONTROL')
    end
  end

  describe 'an instrument with a blank identifier' do
    # `if instrument.id` guards nil, not blank, and "" is truthy, so a
    # record carrying `id: ""` used to reach the sanitizer and raise.
    def citation_for(id)
      instrument = Ammitto::Sources::Cn::Instrument.new(id: id,
                                                        law: 'Order 123')
      transformer.send(:create_legal_citations, [instrument]).first
    end

    it 'falls back to the law rather than raising' do
      expect(citation_for('').legal_instrument_id).to include('order-123')
    end

    it 'still falls back when the id is absent' do
      expect(citation_for(nil).legal_instrument_id).to include('order-123')
    end

    it 'falls back when the id contains only whitespace' do
      expect(citation_for('   ').legal_instrument_id).to include('order-123')
    end

    it 'falls back when the prefixed id has no local part' do
      expect(citation_for('cn/   ').legal_instrument_id).to include('order-123')
    end

    it 'still uses a real id, with the cn/ prefix stripped' do
      expect(citation_for(' cn/mofcom-2025-14 ').legal_instrument_id)
        .to end_with('/cn/mofcom-2025-14')
    end

    # The law is the fallback, so a record with neither must still fail
    # loudly. Routing the law through `sanitize_id` first would hand back
    # DEFAULT_ID and collapse every such record onto one shared
    # `.../legal_instrument/cn/unknown`, which is what iri_sanitizer.rb
    # raises to prevent.
    it 'raises rather than collapsing when neither the id nor the law is usable' do
      %w[law_blank law_nil].zip(['', nil]).each do |_name, law|
        instrument = Ammitto::Sources::Cn::Instrument.new(id: '', law: law)

        expect { transformer.send(:create_legal_citations, [instrument]) }
          .to raise_error(Ammitto::Utils::IriSanitizer::MissingLocalIdError)
      end
    end
  end

  describe 'an announcement reference with an unusable document_id' do
    let(:entity) do
      Ammitto::Sources::Cn::Entity.new(
        name: { 'zh-Hans' => '北京ABC科技有限公司', 'en' => 'Beijing ABC' },
        type: 'organization'
      )
    end

    def reference_for(announcement_fields)
      announcement = Ammitto::Sources::Cn::Announcement.from_hash(
        'announcement' => announcement_fields
      )
      transformer.send(:create_entity_reference, entity, announcement)
    end

    # `sanitize_id` returns DEFAULT_ID for every id it cannot use, but the
    # old `||` fallback only rejected nil. So an entity's reference
    # depended on how its source spelled "no document id": an absent one
    # gave "cn-", and each of these gave "unknown-".
    it 'treats a blank document_id the same as an absent one' do
      blank = reference_for('document_id' => '')

      expect(blank).to eq(reference_for({}))
      expect(blank).to start_with('cn-')
    end

    it 'treats a whitespace-only document_id the same as an absent one' do
      whitespace = reference_for('document_id' => "  \t ")

      expect(whitespace).to eq(reference_for({}))
      expect(whitespace).to start_with('cn-')
    end

    # The shape this source actually produces: a document id written in
    # Chinese leaves no ASCII behind, so the sanitizer cannot build an id
    # from it either.
    it 'treats a document_id that sanitizes to nothing as an absent one' do
      cjk = reference_for('document_id' => '公告')

      expect(Ammitto::Utils::IriSanitizer.sanitize('公告'))
        .to eq(Ammitto::Utils::IriSanitizer::DEFAULT_ID)
      expect(cjk).to eq(reference_for({}))
      expect(cjk).to start_with('cn-')
    end

    # A source that writes the word out is spelling "no id" as well. It
    # joins the same bucket, which separates nothing main held apart: it
    # already sanitized to DEFAULT_ID alongside the blank and CJK cases.
    it 'treats a literal "unknown" document_id as an absent one' do
      literal = reference_for(
        'document_id' => Ammitto::Utils::IriSanitizer::DEFAULT_ID
      )

      expect(literal).to eq(reference_for({}))
      expect(literal).to start_with('cn-')
    end

    it 'still uses a document_id the sanitizer can build an id from' do
      usable = reference_for('document_id' => 'mofcom-2026-01')

      expect(usable).to start_with('mofcom-2026-01-')
    end
  end
end
