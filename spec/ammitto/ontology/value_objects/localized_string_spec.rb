# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/ontology/value_objects/localized_string'

RSpec.describe Ammitto::Ontology::ValueObjects::LocalizedString do
  describe '#initialize' do
    it 'creates a localized string with all attributes' do
      ls = described_class.new(
        value: '三菱重工業株式会社',
        language: 'zh',
        script: 'Hani',
        region: 'CN',
        is_primary: true,
        is_transliteration: false,
        transliteration_system: 'pinyin'
      )

      expect(ls.value).to eq('三菱重工業株式会社')
      expect(ls.language).to eq('zh')
      expect(ls.script).to eq('Hani')
      expect(ls.region).to eq('CN')
      expect(ls.is_primary).to be true
      expect(ls.is_transliteration).to be false
      expect(ls.transliteration_system).to eq('pinyin')
    end

    it 'defaults is_primary to false' do
      ls = described_class.new(value: 'Test')
      expect(ls.is_primary).to be false
    end

    it 'defaults is_transliteration to false' do
      ls = described_class.new(value: 'Test')
      expect(ls.is_transliteration).to be false
    end
  end

  describe '#primary?' do
    it 'returns true when is_primary is true' do
      ls = described_class.new(value: 'Test', is_primary: true)
      expect(ls.primary?).to be true
    end

    it 'returns false when is_primary is false' do
      ls = described_class.new(value: 'Test', is_primary: false)
      expect(ls.primary?).to be false
    end
  end

  describe '#transliteration?' do
    it 'returns true when is_transliteration is true' do
      ls = described_class.new(value: 'Test', is_transliteration: true)
      expect(ls.transliteration?).to be true
    end

    it 'returns false when is_transliteration is false' do
      ls = described_class.new(value: 'Test', is_transliteration: false)
      expect(ls.transliteration?).to be false
    end
  end

  describe '#non_latin?' do
    it 'returns true for non-Latin scripts' do
      ls = described_class.new(value: 'Иван', script: 'Cyrl')
      expect(ls.non_latin?).to be true
    end

    it 'returns true for Han script' do
      ls = described_class.new(value: '中国', script: 'Hani')
      expect(ls.non_latin?).to be true
    end

    it 'returns false for Latin script' do
      ls = described_class.new(value: 'Test', script: 'Latn')
      expect(ls.non_latin?).to be false
    end

    it 'returns false when script is nil' do
      ls = described_class.new(value: 'Test')
      expect(ls.non_latin?).to be false
    end
  end

  describe '#language_tag' do
    it 'constructs language tag from components' do
      ls = described_class.new(
        value: '中国',
        language: 'zh',
        script: 'Hani',
        region: 'CN'
      )
      expect(ls.language_tag).to eq('zh-Hani-CN')
    end

    it 'returns nil when no language components' do
      ls = described_class.new(value: 'Test')
      expect(ls.language_tag).to be_nil
    end

    it 'handles partial components' do
      ls = described_class.new(value: 'Test', language: 'en')
      expect(ls.language_tag).to eq('en')
    end
  end

  describe '.from_language_tag' do
    it 'parses full language tag' do
      ls = described_class.from_language_tag('zh-Hans-CN', value: '中国', is_primary: true)

      expect(ls.value).to eq('中国')
      expect(ls.language).to eq('zh')
      expect(ls.script).to eq('Hans')
      expect(ls.region).to eq('CN')
      expect(ls.is_primary).to be true
    end

    it 'parses language-only tag' do
      ls = described_class.from_language_tag('en', value: 'Test')

      expect(ls.value).to eq('Test')
      expect(ls.language).to eq('en')
      expect(ls.script).to be_nil
      expect(ls.region).to be_nil
    end

    it 'parses language-script tag' do
      ls = described_class.from_language_tag('zh-Hant', value: '繁體')

      expect(ls.language).to eq('zh')
      expect(ls.script).to eq('Hant')
    end
  end

  describe 'serialization' do
    it 'serializes to JSON' do
      ls = described_class.new(
        value: '三菱重工業株式会社',
        language: 'zh',
        script: 'Hani',
        is_primary: true
      )
      json = ls.to_json
      parsed = JSON.parse(json)

      expect(parsed['value']).to eq('三菱重工業株式会社')
      expect(parsed['lang']).to eq('zh')
      expect(parsed['script']).to eq('Hani')
      expect(parsed['is_primary']).to be true
    end

    it 'deserializes from JSON' do
      json = '{"value":"Test","lang":"en","script":"Latn","is_primary":true}'
      ls = described_class.from_json(json)

      expect(ls.value).to eq('Test')
      expect(ls.language).to eq('en')
      expect(ls.script).to eq('Latn')
      expect(ls.is_primary).to be true
    end

    it 'serializes to YAML' do
      ls = described_class.new(
        value: 'Test',
        language: 'en',
        script: 'Latn'
      )
      yaml = ls.to_yaml
      expect(yaml).to include('value: Test')
      expect(yaml).to include('lang: en')
      expect(yaml).to include('script: Latn')
    end
  end
end
