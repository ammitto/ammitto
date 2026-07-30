# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/cn/announcement'
require 'ammitto/sources/cn/transformer'

RSpec.describe Ammitto::Sources::Cn::Entity do
  describe '#list_type_code' do
    def code_for(value)
      described_class.new(sanction_list: value).list_type_code
    end

    it 'matches the Chinese labels from the schema enum' do
      expect(code_for('反制裁清单')).to eq('anti_sanctions')
      expect(code_for('不可靠实体清单')).to eq('unreliable_entity')
      expect(code_for('出口管制管控名单')).to eq('export_control')
    end

    it 'matches the source-prefixed slugs the data stores' do
      expect(code_for('cn/anti-sanction-list')).to eq('anti_sanctions')
      expect(code_for('cn/unreliable-entity-list')).to eq('unreliable_entity')
      expect(code_for('cn/import-export-control-list')).to eq('export_control')
    end

    it 'matches bare slugs without the source prefix' do
      expect(code_for('anti-sanction-list')).to eq('anti_sanctions')
      expect(code_for('unreliable-entity-list')).to eq('unreliable_entity')
      expect(code_for('import-export-control-list')).to eq('export_control')
    end

    it 'ignores surrounding whitespace' do
      expect(code_for(" cn/anti-sanction-list\n")).to eq('anti_sanctions')
    end

    it 'returns unknown for unrecognized, empty, and nil values' do
      expect(code_for('no-such-list')).to eq('unknown')
      expect(code_for('')).to eq('unknown')
      expect(code_for(nil)).to eq('unknown')
    end
  end
end

RSpec.describe Ammitto::Sources::Cn::Transformer do
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
end
