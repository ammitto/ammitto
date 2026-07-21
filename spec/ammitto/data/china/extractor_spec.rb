# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/data/china/extractor'

RSpec.describe Ammitto::Data::China::Extractor do
  describe '.available_sources' do
    it 'returns list of available sources' do
      expect(described_class.available_sources).to include('mofcom-unreliable-entity-list')
      expect(described_class.available_sources).to include('mfa-anti-sanction-list')
    end
  end

  describe '.valid_source?' do
    it 'returns true for valid sources' do
      expect(described_class.valid_source?('mofcom-unreliable-entity-list')).to be true
      expect(described_class.valid_source?('unknown-source')).to be false
    end
  end

  describe '#fetch' do
    let(:extractor) { described_class.new('mofcom-unreliable-entity-list') }

    before do
      # Mock web requests
      allow(extractor).to receive(:agent).and_return(mock_agent)
    end

    it 'returns array of extracted data' do
      result = extractor.fetch
      expect(result).to be_an(Array)
    end

    it 'raises error for unknown source' do
      expect { described_class.new('unknown').fetch }.to raise_error(ArgumentError)
    end

    def mock_agent
      instance_double(Mechanize).tap do |a|
        allow(a).to receive(:get).and_return(mock_page)
      end
    end

    def mock_page
      instance_double(Mechanize::Page).tap do |p|
        allow(p).to receive(:links).and_return([])
        allow(p).to receive(:uri).and_return(URI('https://example.com'))
        allow(p).to receive(:body).and_return('')
        allow(p).to receive(:at).and_return(nil)
        allow(p).to receive(:title).and_return('Test')
      end
    end
  end
end
