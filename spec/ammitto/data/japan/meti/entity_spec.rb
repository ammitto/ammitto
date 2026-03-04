# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/data/japan/meti/entity'

RSpec.describe Ammitto::Data::Japan::METI::Entity do
  let(:entity) do
    described_class.new(
      id: 'jp.meti.ful.1',
      name_en: "Al Qa'ida/Islamic Army",
      country_code: 'AF',
      country_ja: 'アフガニスタン',
      country_en: 'Islamic Republic of Afghanistan',
      wmd_types: %w[B C M N CW],
      aliases: ['Al Qaeda', 'Islamic Salvation Foundation'],
      entity_type: 'organization',
      source_file: '20250929_4.xlsx',
      source_url: 'https://www.meti.go.jp/policy/anpo/20250929_4.xlsx',
      list_date: '2025-09-29',
      row_number: 1
    )
  end

  describe '#primary_name' do
    it 'returns English name when available' do
      expect(entity.primary_name).to eq("Al Qa'ida/Islamic Army")
    end

    it 'returns Japanese name when English not available' do
      entity.name_en = nil
      entity.name_ja = 'テスト組織'
      expect(entity.primary_name).to eq('テスト組織')
    end
  end

  describe '#reference_number' do
    it 'extracts the reference number from ID' do
      expect(entity.reference_number).to eq('1')
    end
  end

  describe '#wmd_descriptions' do
    it 'returns WMD type descriptions' do
      descriptions = entity.wmd_descriptions

      expect(descriptions).to be_an(Array)
      expect(descriptions.first[:code]).to eq('B')
      expect(descriptions.first[:en]).to eq('Biological weapons')
    end
  end

  describe '#country_name' do
    it 'returns country name hash' do
      expect(entity.country_name).to eq({
                                          ja: 'アフガニスタン',
                                          en: 'Islamic Republic of Afghanistan'
                                        })
    end
  end

  describe '#to_hash' do
    it 'converts entity to hash' do
      hash = entity.to_hash

      expect(hash['id']).to eq('jp.meti.ful.1')
      expect(hash['name']).to eq({ 'en' => "Al Qa'ida/Islamic Army" })
      expect(hash['type']).to eq('organization')
      expect(hash['country_code']).to eq('AF')
      expect(hash['wmd_types']).to eq(%w[B C M N CW])
      expect(hash['aliases']).to eq(['Al Qaeda', 'Islamic Salvation Foundation'])
    end

    it 'omits nil values' do
      entity.aliases = []
      hash = entity.to_hash

      expect(hash).not_to have_key('aliases')
    end
  end

  describe 'XML serialization' do
    it 'serializes to XML' do
      xml = entity.to_xml

      expect(xml).to include('<Entity>')
      expect(xml).to include('<ID>jp.meti.ful.1</ID>')
      expect(xml).to include('<NameEN>Al Qa\'ida/Islamic Army</NameEN>')
      expect(xml).to include('<CountryCode>AF</CountryCode>')
    end

    it 'deserializes from XML' do
      xml = entity.to_xml
      parsed = described_class.from_xml(xml)

      expect(parsed.id).to eq('jp.meti.ful.1')
      expect(parsed.name_en).to eq("Al Qa'ida/Islamic Army")
      expect(parsed.country_code).to eq('AF')
    end
  end
end
