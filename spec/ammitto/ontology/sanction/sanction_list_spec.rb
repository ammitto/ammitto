# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/ontology/sanction/sanction_list'
require 'ammitto/ontology/sanction/authority'
require 'ammitto/ontology/sanction/sanction_regime'

RSpec.describe Ammitto::Ontology::Sanction::SanctionList do
  let(:authority) do
    Ammitto::Ontology::Sanction::Authority.new(
      id: 'cn',
      name: 'Ministry of Commerce of China'
    )
  end

  let(:regime) do
    Ammitto::Ontology::Sanction::SanctionRegime.new(
      code: 'CN_UEL',
      name: 'Unreliable Entity List'
    )
  end

  describe '#initialize' do
    it 'creates a sanction list with all attributes' do
      list = described_class.new(
        id: 'https://www.ammitto.org/list/cn/UEL',
        source: 'cn',
        code: 'UEL',
        authority: authority,
        regime: regime,
        list_type: 'primary',
        status: 'active',
        established_date: Date.new(2020, 9, 19),
        url: 'http://mofcom.gov.cn'
      )

      expect(list.id).to eq('https://www.ammitto.org/list/cn/UEL')
      expect(list.source).to eq('cn')
      expect(list.code).to eq('UEL')
      expect(list.authority).to eq(authority)
      expect(list.regime).to eq(regime)
      expect(list.list_type).to eq('primary')
      expect(list.status).to eq('active')
      expect(list.established_date).to eq(Date.new(2020, 9, 19))
      expect(list.url).to eq('http://mofcom.gov.cn')
    end

    it 'defaults status to active' do
      list = described_class.new(id: 'test')
      expect(list.status).to eq('active')
    end
  end

  describe '#active?' do
    it 'returns true when status is active' do
      list = described_class.new(status: 'active')
      expect(list.active?).to be true
    end

    it 'returns false when status is not active' do
      list = described_class.new(status: 'inactive')
      expect(list.active?).to be false
    end
  end

  describe '#inactive?' do
    it 'returns true when status is inactive' do
      list = described_class.new(status: 'inactive')
      expect(list.inactive?).to be true
    end

    it 'returns false when status is not inactive' do
      list = described_class.new(status: 'active')
      expect(list.inactive?).to be false
    end
  end

  describe 'with multilingual names' do
    let(:name_zh) do
      Ammitto::Ontology::ValueObjects::LocalizedString.new(
        value: '不可靠实体清单',
        language: 'zh',
        script: 'Hani',
        is_primary: true
      )
    end

    let(:name_en) do
      Ammitto::Ontology::ValueObjects::LocalizedString.new(
        value: 'Unreliable Entity List',
        language: 'en',
        script: 'Latn'
      )
    end

    it 'stores multilingual names' do
      list = described_class.new(name: [name_zh, name_en])
      expect(list.name).to eq([name_zh, name_en])
    end
  end

  describe '#primary_name' do
    let(:name_zh) do
      Ammitto::Ontology::ValueObjects::LocalizedString.new(
        value: '不可靠实体清单',
        language: 'zh',
        is_primary: true
      )
    end

    let(:name_en) do
      Ammitto::Ontology::ValueObjects::LocalizedString.new(
        value: 'Unreliable Entity List',
        language: 'en'
      )
    end

    it 'returns the first primary name' do
      list = described_class.new(name: [name_en, name_zh])
      expect(list.primary_name).to eq(name_zh)
    end

    it 'returns first name when no primary is set' do
      list = described_class.new(name: [name_en])
      expect(list.primary_name).to eq(name_en)
    end

    it 'returns nil when no names' do
      list = described_class.new
      expect(list.primary_name).to be_nil
    end
  end

  describe '#name_in_language' do
    let(:name_zh) do
      Ammitto::Ontology::ValueObjects::LocalizedString.new(
        value: '不可靠实体清单',
        language: 'zh'
      )
    end

    let(:name_en) do
      Ammitto::Ontology::ValueObjects::LocalizedString.new(
        value: 'Unreliable Entity List',
        language: 'en'
      )
    end

    it 'returns name in specified language' do
      list = described_class.new(name: [name_zh, name_en])
      expect(list.name_in_language('en')).to eq(name_en)
      expect(list.name_in_language('zh')).to eq(name_zh)
    end

    it 'returns nil when language not found' do
      list = described_class.new(name: [name_en])
      expect(list.name_in_language('fr')).to be_nil
    end
  end

  describe 'serialization' do
    let(:list) do
      described_class.new(
        id: 'https://www.ammitto.org/list/cn/UEL',
        source: 'cn',
        code: 'UEL',
        list_type: 'primary',
        status: 'active'
      )
    end

    it 'serializes to JSON' do
      json = list.to_json
      parsed = JSON.parse(json)

      expect(parsed['id']).to eq('https://www.ammitto.org/list/cn/UEL')
      expect(parsed['source']).to eq('cn')
      expect(parsed['code']).to eq('UEL')
      expect(parsed['list_type']).to eq('primary')
      expect(parsed['status']).to eq('active')
    end

    it 'deserializes from JSON' do
      json = '{"id":"test","source":"cn","code":"UEL","status":"active"}'
      result = described_class.from_json(json)

      expect(result.id).to eq('test')
      expect(result.source).to eq('cn')
      expect(result.code).to eq('UEL')
      expect(result.status).to eq('active')
    end
  end
end
