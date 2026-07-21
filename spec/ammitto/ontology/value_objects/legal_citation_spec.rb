# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/ontology/value_objects/legal_citation'
require 'ammitto/ontology/value_objects/localized_string'

RSpec.describe Ammitto::Ontology::ValueObjects::LegalCitation do
  describe '#initialize' do
    it 'creates a legal citation with all attributes' do
      citation = described_class.new(
        id: 'https://www.ammitto.org/citation/cn/2021-art4',
        legal_instrument_id: 'https://www.ammitto.org/instrument/cn/afscl',
        articles: %w[第四条 第五条],
        sections: ['第一项'],
        paragraphs: ['1'],
        citation_type: 'legal_basis',
        context: 'Primary legal authority'
      )

      expect(citation.id).to eq('https://www.ammitto.org/citation/cn/2021-art4')
      expect(citation.legal_instrument_id).to eq('https://www.ammitto.org/instrument/cn/afscl')
      expect(citation.articles).to eq(%w[第四条 第五条])
      expect(citation.sections).to eq(['第一项'])
      expect(citation.paragraphs).to eq(['1'])
      expect(citation.citation_type).to eq('legal_basis')
      expect(citation.context).to eq('Primary legal authority')
    end
  end

  describe '#legal_basis?' do
    it 'returns true for legal_basis citation type' do
      citation = described_class.new(citation_type: 'legal_basis')
      expect(citation.legal_basis?).to be true
    end

    it 'returns false for other citation types' do
      citation = described_class.new(citation_type: 'reference')
      expect(citation.legal_basis?).to be false
    end
  end

  describe '#amendment?' do
    it 'returns true for amendment citation type' do
      citation = described_class.new(citation_type: 'amendment')
      expect(citation.amendment?).to be true
    end

    it 'returns false for other citation types' do
      citation = described_class.new(citation_type: 'legal_basis')
      expect(citation.amendment?).to be false
    end
  end

  describe '#display' do
    it 'returns formatted display string with articles' do
      citation = described_class.new(
        legal_instrument_id: 'test-law',
        articles: %w[第一条 第二条]
      )
      expect(citation.display).to eq('Art. 第一条, 第二条')
    end

    it 'returns formatted display string with sections' do
      citation = described_class.new(
        legal_instrument_id: 'test-law',
        sections: ['第一项']
      )
      expect(citation.display).to eq('Sec. 第一项')
    end

    it 'returns formatted display string with paragraphs' do
      citation = described_class.new(
        legal_instrument_id: 'test-law',
        paragraphs: %w[1 2]
      )
      expect(citation.display).to eq('Para. 1, 2')
    end

    it 'returns legal instrument ID when no provisions' do
      citation = described_class.new(legal_instrument_id: 'test-law')
      expect(citation.display).to eq('test-law')
    end
  end

  describe '#all_provisions' do
    it 'combines all provisions into flat array' do
      citation = described_class.new(
        articles: ['第一条'],
        sections: ['第一項'],
        paragraphs: ['1']
      )
      expect(citation.all_provisions).to eq(%w[第一条 第一項 1])
    end

    it 'returns empty array when no provisions' do
      citation = described_class.new
      expect(citation.all_provisions).to eq([])
    end
  end

  describe '#provisions?' do
    it 'returns true when provisions exist' do
      citation = described_class.new(articles: ['第一条'])
      expect(citation.provisions?).to be true
    end

    it 'returns false when no provisions' do
      citation = described_class.new
      expect(citation.provisions?).to be false
    end
  end

  describe 'serialization' do
    let(:citation) do
      described_class.new(
        id: 'https://www.ammitto.org/citation/cn/2021-art4',
        legal_instrument_id: 'https://www.ammitto.org/instrument/cn/afscl',
        articles: ['第四条'],
        citation_type: 'legal_basis',
        context: 'Primary authority'
      )
    end

    it 'serializes to JSON' do
      json = citation.to_json
      parsed = JSON.parse(json)

      expect(parsed['id']).to eq('https://www.ammitto.org/citation/cn/2021-art4')
      expect(parsed['legal_instrument_id']).to eq('https://www.ammitto.org/instrument/cn/afscl')
      expect(parsed['articles']).to eq(['第四条'])
      expect(parsed['citation_type']).to eq('legal_basis')
    end

    it 'deserializes from JSON' do
      json = '{"id":"test","legal_instrument_id":"inst","articles":["第一条"],"citation_type":"legal_basis"}'
      result = described_class.from_json(json)

      expect(result.id).to eq('test')
      expect(result.legal_instrument_id).to eq('inst')
      expect(result.articles).to eq(['第一条'])
      expect(result.citation_type).to eq('legal_basis')
    end
  end
end
