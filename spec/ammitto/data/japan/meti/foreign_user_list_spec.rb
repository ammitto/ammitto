# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'ammitto/data/japan/meti/foreign_user_list'

RSpec.describe Ammitto::Data::Japan::METI::ForeignUserList do
  let(:sample_xlsx) { 'spec/fixtures/japan/meti/sample_foreign_user_list.xlsx' }

  describe '.from_xlsx' do
    context 'with valid Excel file' do
      it 'parses entities from the Excel file' do
        skip 'Requires sample Excel fixture file'

        list = described_class.from_xlsx(sample_xlsx, source_url: 'https://example.com/list.xlsx')

        expect(list.entities).to be_an(Array)
        expect(list.entities.count).to be > 0
        expect(list.source_file).to eq('sample_foreign_user_list.xlsx')
        expect(list.source_url).to eq('https://example.com/list.xlsx')
      end
    end
  end

  describe '.parse_bilingual_text' do
    it 'parses Japanese and English separated by newline' do
      result = described_class.parse_bilingual_text("アフガニスタン\nIslamic Republic of Afghanistan")

      expect(result[:ja]).to eq('アフガニスタン')
      expect(result[:en]).to eq('Islamic Republic of Afghanistan')
    end

    it 'handles Japanese-only text' do
      result = described_class.parse_bilingual_text('日本')

      expect(result[:ja]).to eq('日本')
      expect(result[:en]).to be_nil
    end

    it 'handles English-only text' do
      result = described_class.parse_bilingual_text('United States')

      expect(result[:ja]).to be_nil
      expect(result[:en]).to eq('United States')
    end

    it 'handles nil input' do
      result = described_class.parse_bilingual_text(nil)

      expect(result[:ja]).to be_nil
      expect(result[:en]).to be_nil
    end
  end

  describe '.parse_aliases' do
    it 'parses aliases separated by newlines with bullet points' do
      result = described_class.parse_aliases("・Al Qaeda\n・Islamic Salvation Foundation\n・The Base")

      expect(result).to eq(['Al Qaeda', 'Islamic Salvation Foundation', 'The Base'])
    end

    it 'handles nil input' do
      expect(described_class.parse_aliases(nil)).to eq([])
    end

    it 'handles empty strings' do
      expect(described_class.parse_aliases('')).to eq([])
    end
  end

  describe '.extract_wmd_codes' do
    it 'extracts standard WMD codes' do
      codes = described_class.extract_wmd_codes("核\nN", nil)
      expect(codes).to eq(['N'])
    end

    it 'extracts multiple WMD codes' do
      codes = described_class.extract_wmd_codes("生物、化学、ミサイル、核\nB,C,M,N", nil)
      expect(codes).to contain_exactly('B', 'C', 'M', 'N')
    end

    it 'handles fullwidth characters' do
      codes = described_class.extract_wmd_codes("核\nＮ", nil)
      expect(codes).to eq(['N'])
    end

    it 'extracts conventional weapons code' do
      codes = described_class.extract_wmd_codes(nil, "通常兵器\nCW")
      expect(codes).to eq(['CW'])
    end
  end

  describe '.lookup_country_code' do
    it 'finds country by Japanese name' do
      code = described_class.lookup_country_code('イラン', nil)
      expect(code).to eq('IR')
    end

    it 'finds country by English name' do
      code = described_class.lookup_country_code(nil, 'North Korea')
      expect(code).to eq('KP')
    end

    it 'handles partial Japanese name match' do
      code = described_class.lookup_country_code('ロシア連邦', nil)
      expect(code).to eq('RU')
    end

    it 'returns nil for unknown country' do
      code = described_class.lookup_country_code('Unknown Country', nil)
      expect(code).to be_nil
    end
  end

  describe '.extract_date_from_filename' do
    it 'extracts date from filename with YYYYMMDD format' do
      date = described_class.extract_date_from_filename('20250929_4.xlsx')
      expect(date).to eq('2025-09-29')
    end

    it 'returns today date for filename without date' do
      date = described_class.extract_date_from_filename('foreign_user_list.xlsx')
      expect(date).to eq(Date.today.to_s)
    end
  end

  describe '#find_by_id' do
    let(:list) do
      described_class.new(
        entities: [
          Ammitto::Data::Japan::METI::Entity.new(id: 'jp.meti.ful.1', name_en: 'Entity 1'),
          Ammitto::Data::Japan::METI::Entity.new(id: 'jp.meti.ful.2', name_en: 'Entity 2')
        ]
      )
    end

    it 'finds entity by ID' do
      entity = list.find_by_id('jp.meti.ful.1')
      expect(entity.name_en).to eq('Entity 1')
    end

    it 'returns nil for non-existent ID' do
      expect(list.find_by_id('jp.meti.ful.999')).to be_nil
    end
  end

  describe '#find_by_country' do
    let(:list) do
      described_class.new(
        entities: [
          Ammitto::Data::Japan::METI::Entity.new(id: '1', name_en: 'Entity 1', country_code: 'IR'),
          Ammitto::Data::Japan::METI::Entity.new(id: '2', name_en: 'Entity 2', country_code: 'IR'),
          Ammitto::Data::Japan::METI::Entity.new(id: '3', name_en: 'Entity 3', country_code: 'KP')
        ]
      )
    end

    it 'finds entities by country code' do
      entities = list.find_by_country('IR')
      expect(entities.count).to eq(2)
    end
  end

  describe '#find_by_wmd_type' do
    let(:list) do
      described_class.new(
        entities: [
          Ammitto::Data::Japan::METI::Entity.new(id: '1', name_en: 'Entity 1', wmd_types: %w[N M]),
          Ammitto::Data::Japan::METI::Entity.new(id: '2', name_en: 'Entity 2', wmd_types: %w[N]),
          Ammitto::Data::Japan::METI::Entity.new(id: '3', name_en: 'Entity 3', wmd_types: %w[C])
        ]
      )
    end

    it 'finds entities by WMD type' do
      entities = list.find_by_wmd_type('N')
      expect(entities.count).to eq(2)
    end
  end

  describe '#to_hash' do
    let(:list) do
      described_class.new(
        source_file: 'test.xlsx',
        source_url: 'https://example.com/test.xlsx',
        list_date: '2025-09-29',
        fetched_at: '2025-09-29T10:00:00Z',
        entities: [
          Ammitto::Data::Japan::METI::Entity.new(id: 'jp.meti.ful.1', name_en: 'Test Entity')
        ]
      )
    end

    it 'converts to hash for YAML serialization' do
      hash = list.to_hash

      expect(hash['source_file']).to eq('test.xlsx')
      expect(hash['source_url']).to eq('https://example.com/test.xlsx')
      expect(hash['list_date']).to eq('2025-09-29')
      expect(hash['entities']).to be_an(Array)
      expect(hash['entities'].first['id']).to eq('jp.meti.ful.1')
    end
  end
end
