# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/cn/announcement'
require 'ammitto/sources/cn/transformer'

# Builds the announcements and modifications the examples feed the transformer.
module CnTransformerSpecHelpers
  def listing(names, document_id: '2026年第11号')
    Ammitto::Sources::Cn::Announcement.from_hash(
      'announcement' => { 'document_id' => document_id },
      'sanction_details' => {
        'entities' => names.map do |name|
          { 'name' => { 'en' => name }, 'type' => 'organization',
            'effective_date' => '2026-02-24', 'sanction_list' => 'cn/export-control-list' }
        end
      }
    )
  end

  def entity_ids(names)
    described_class.new.transform_announcement(listing(names))[:entities].map(&:id)
  end

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
      announcement.sanction_details = Ammitto::Sources::Cn::SanctionDetails.new(entities: [entity])
      transformer.send(:announcement_references, announcement).fetch(entity)
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

    it 'counts no affected parties as 0 when the source names none' do
      modification = Ammitto::Sources::Cn::Modification.new(target_announcement_id: '〔2025〕7号')
      result = described_class.new.send(:create_sanction_period_modification,
                                        modification: modification,
                                        announcement_id: 'https://www.ammitto.org/announcement/cn/abc')

      expect(result.affected_entity_count).to eq(0)
    end

    it 'carries the names of the affected parties' do
      modification = Ammitto::Sources::Cn::Modification.new(
        target_announcement_id: '〔2025〕7号', affected_entity_names: %w[Skydio PVH]
      )
      result = described_class.new.send(:create_sanction_period_modification,
                                        modification: modification,
                                        announcement_id: 'https://www.ammitto.org/announcement/cn/abc')

      expect([result.affected_entity_names, result.affected_entity_count]).to eq([%w[Skydio PVH], 2])
    end

    it 'still names a modification whose target the sanitizer can use' do
      expect(modify('〔2025〕7号').id)
        .to eq('https://www.ammitto.org/modification/cn/abc-20257')
    end
  end

  describe 'parties whose cut names clash in one announcement' do
    # Real party names from data-cn import-export-control-list/202611.yml
    let(:marine) { 'Mitsubishi Heavy Industries Marine Machinery & Equipment Co., Ltd.' }
    let(:maritime) { 'Mitsubishi Heavy Industries Maritime Systems, Ltd.' }
    let(:base) { 'https://www.ammitto.org/entity/cn/202611-' }

    it 'keeps the cut-name id when nothing clashes' do
      expect(entity_ids([marine, 'Short Co'])).to eq(["#{base}mitsubishi-heavy-industries-mar", "#{base}short-co"])
    end

    it 'gives each clashing party its full-name id' do
      expect(entity_ids([marine, maritime, 'Short Co'])).to eq(
        ["#{base}mitsubishi-heavy-industries-marine-machinery-equipment-co",
         "#{base}mitsubishi-heavy-industries-maritime-systems-ltd", "#{base}short-co"]
      )
    end

    it 'gives the same ids whatever the listing order' do
      expect(entity_ids([maritime, marine]).sort).to eq(entity_ids([marine, maritime]).sort)
    end

    it 'numbers the parties in notice order when full names still clash, and warns' do
      allow(Ammitto::Logger).to receive(:warn)

      expect(entity_ids([marine, 'Short Co', marine])).to eq(
        ["#{base}mitsubishi-heavy-industries-marine-machinery-equipment-1", "#{base}short-co",
         "#{base}mitsubishi-heavy-industries-marine-machinery-equipment-2"]
      )
      expect(Ammitto::Logger).to have_received(:warn).once
                                                     .with(/2026年第11号: parties share one id even after taking full names, .*#{Regexp.escape(marine)}/)
    end

    it 'gives a numbered party\'s entry the same reference as its entity' do
      allow(Ammitto::Logger).to receive(:warn)
      result = described_class.new.transform_announcement(listing([marine, marine]))
      refs = result[:entities].map { |e| e.id.split('/').last }

      expect(result[:entries].map { |e| e.id.split('/').last }).to eq(refs)
      expect(result[:entries].map(&:reference_number)).to eq(refs)
    end

    it 'numbers a full-name id that meets another party\'s cut id' do
      allow(Ammitto::Logger).to receive(:warn)
      prefix = "Foo#{'.' * 28}"

      expect(entity_ids(["#{prefix}-X", "#{prefix}-Y", 'Foo-X'])).to eq(
        ["#{base}foo-x-1", "#{base}foo-y", "#{base}foo-x-2"]
      )
    end

    it 'skips a number another party already holds' do
      allow(Ammitto::Logger).to receive(:warn)

      expect(entity_ids(['Short Co', 'Short Co-1', 'Short Co'])).to eq(
        ["#{base}short-co-2", "#{base}short-co-1", "#{base}short-co-3"]
      )
    end

    it 'keeps the number when the full-name reference fills the 64-character id' do
      # 40 + '-' + 23 shared characters is exactly 64: the references first
      # differ at character 65, the first one the sanitizer cuts away.
      allow(Ammitto::Logger).to receive(:warn)
      long_doc = 'a' * 40
      names = ["#{'b' * 23}x", "#{'b' * 23}y"]
      ids = described_class.new.transform_announcement(listing(names, document_id: long_doc))[:entities].map(&:id)

      expect(ids.map { |id| id.split('/').last }).to eq(
        ["#{'a' * 40}-#{'b' * 21}-1", "#{'a' * 40}-#{'b' * 21}-2"]
      )
    end

    it 'does not warn when full names resolve the clash' do
      allow(Ammitto::Logger).to receive(:warn)
      entity_ids([marine, maritime])

      expect(Ammitto::Logger).not_to have_received(:warn)
    end
  end
end
