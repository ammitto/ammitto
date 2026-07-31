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
end
