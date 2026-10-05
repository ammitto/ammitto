# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/cn/announcement'
require 'ammitto/sources/cn/transformer'

# Builds the announcements and modifications the examples feed the transformer.
module CnTransformerSpecHelpers
  def announcement_with(publish_date:, effective_dates:)
    Ammitto::Sources::Cn::Announcement.from_hash(
      'announcement' => { 'document_id' => 'mofcom-2026-02', 'publish_date' => publish_date },
      'sanction_details' => {
        'entities' => effective_dates.each_with_index.map do |date, i|
          { 'name' => { 'en' => "Corp #{i}" }, 'type' => 'organization',
            'effective_date' => date, 'sanction_list' => 'cn/anti-sanction-list' }
        end
      }
    )
  end

  def announce(document_id)
    announcement = Ammitto::Sources::Cn::Announcement.from_hash(
      'announcement' => { 'document_id' => document_id }
    )
    described_class.new.transform_announcement(announcement)
  end

  def modify(target_id)
    modification = Ammitto::Sources::Cn::Modification.new(target_announcement_id: target_id)
    described_class.new.send(:create_sanction_period_modification,
                             modification: modification,
                             announcement_id: 'https://www.ammitto.org/announcement/cn/abc')
  end
end

RSpec.describe Ammitto::Sources::Cn::Transformer do
  include CnTransformerSpecHelpers

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

  describe 'an entity reference' do
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

    [nil, '', "  \t ", '公告', Ammitto::Utils::IriSanitizer::DEFAULT_ID].each do |id|
      it "refuses a document_id of #{id.inspect} rather than share a reference" do
        expect { reference_for('document_id' => id) }
          .to raise_error(Ammitto::ParseError, /no usable document_id/)
      end
    end

    it 'still uses a document_id the sanitizer can build an id from' do
      usable = reference_for('document_id' => 'mofcom-2026-01')

      expect(usable).to start_with('mofcom-2026-01-')
    end
  end

  describe 'parse failure visibility' do
    include_context 'with parse failure log capture'

    it 'counts an unreadable publish_date once however many entries carry it' do
      result = count_parse_failures do
        transformer.transform_announcement(
          announcement_with(publish_date: 'not-a-date', effective_dates: %w[2026-01-01 2026-01-01])
        )
      end

      expect(result[:official_announcement].publish_date).to be_nil
      expect(io.string.scan('Parse failure in cn.publish_date').size).to eq(1)
      expect(run.count(:cn)).to eq(1)
    end

    it 'counts an unreadable effective_date once, not again for the group' do
      result = count_parse_failures do
        transformer.transform_announcement(
          announcement_with(publish_date: '2026-01-01', effective_dates: %w[not-a-date 2026-01-01])
        )
      end

      expect(result[:entries].first.period.effective_date).to be_nil
      expect(result[:group].effective_date).to be_nil
      expect(io.string).to include('Parse failure in cn.effective_date')
      expect(run.count(:cn)).to eq(1)
    end

    it 'reports each unreadable modification date under its own field name' do
      modification = Ammitto::Sources::Cn::Modification.new(
        target_announcement_id: 'mofcom-2025-01', target_announcement_date: 'bad-target',
        effective_date: 'bad-effective', until_date: 'bad-until'
      )

      period_change = count_parse_failures do
        transformer.send(:create_sanction_period_modification, modification: modification, announcement_id: 'a')
      end

      expect([period_change.target_announcement_date, period_change.effective_date, period_change.until_date])
        .to all(be_nil)
      expect(io.string).to include('Parse failure in cn.target_announcement_date')
        .and include('Parse failure in cn.effective_date')
        .and include('Parse failure in cn.until_date')
      expect(run.count(:cn)).to eq(3)
    end
  end

  # China publishes no expiry, so every period is open ended whether or
  # not the entity carries an effective date.
  describe 'the period of an entity' do
    it 'is indefinite with or without an effective date' do
      announcement = Ammitto::Sources::Cn::Announcement.from_hash(
        'announcement' => { 'document_id' => 'mofcom-2026-02', 'publish_date' => '2026-01-01' },
        'sanction_details' => {
          'entities' => ['2026-01-01', nil].each_with_index.map do |date, i|
            { 'name' => { 'en' => "Corp #{i}" }, 'type' => 'organization',
              'effective_date' => date, 'sanction_list' => 'cn/anti-sanction-list' }
          end
        }
      )

      entries = transformer.transform_announcement(announcement)[:entries]

      expect(entries.map { |entry| entry.period.is_indefinite }).to eq([true, true])
    end
  end

  # Every IRI an announcement or modification mints starts from a document
  # id. One that is absent or sanitizes to the shared fallback would give
  # every such file the same IRI, each overwriting the others in the export.
  describe 'an id that cannot name an announcement' do
    [nil, '', '公告', Ammitto::Utils::IriSanitizer::DEFAULT_ID].each do |id|
      it "refuses an announcement whose document_id is #{id.inspect}" do
        expect { announce(id) }.to raise_error(Ammitto::ParseError, /no usable document_id/)
      end

      it "refuses a modification whose target_announcement_id is #{id.inspect}" do
        expect { modify(id) }.to raise_error(Ammitto::ParseError, /no usable target_announcement_id/)
      end
    end

    # With no block at all, the announcement and its group would share
    # .../announcement/cn/ and .../group/cn/ with every other such file.
    it 'refuses an announcement with no announcement block' do
      announcement = Ammitto::Sources::Cn::Announcement.from_hash(
        'sanction_details' => { 'entities' => [{ 'name' => { 'en' => 'A' } }, { 'name' => { 'en' => 'B' } }] }
      )

      expect { transformer.transform_announcement(announcement) }
        .to raise_error(Ammitto::ParseError, /no usable document_id/)
    end

    it 'still names an announcement whose document_id the sanitizer can use' do
      expect(announce('〔2025〕7号')[:official_announcement].id)
        .to eq('https://www.ammitto.org/announcement/cn/20257')
    end

    it 'still names a modification whose target the sanitizer can use' do
      expect(modify('〔2025〕7号').id)
        .to eq('https://www.ammitto.org/modification/cn/abc-20257')
    end
  end
end
