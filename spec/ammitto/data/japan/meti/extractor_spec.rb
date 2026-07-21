# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/data/japan/meti/extractor'

RSpec.describe Ammitto::Data::Japan::Meti::Extractor do
  let(:extractor) { described_class.new(verbose: true) }

  describe '#code' do
    it 'returns :jp_meti' do
      expect(extractor.code).to eq(:jp_meti)
    end
  end

  describe '#authority_name' do
    it 'returns the authority name' do
      expect(extractor.authority_name).to eq('Japan Meti (Ministry of Economy, Trade and Industry)')
    end
  end

  describe '#api_endpoint' do
    it 'returns the Meti index URL' do
      expect(extractor.api_endpoint).to eq('https://www.meti.go.jp/policy/anpo/law00.html')
    end
  end

  describe '#authority' do
    it 'returns authority hash with correct values' do
      expect(extractor.authority).to eq({
                                          id: 'jp_meti',
                                          name: 'Japan Meti (Ministry of Economy, Trade and Industry)',
                                          country_code: 'JP'
                                        })
    end
  end

  describe '#download', :vcr do
    context 'with live connection' do
      it 'downloads the Excel file', :integration do
        skip 'Requires live network connection'

        path = extractor.download

        expect(File.exist?(path)).to be true
        expect(path).to match(/\.xlsx$/)
        expect(extractor.last_download_url).to match(/meti\.go\.jp/)
      end
    end

    context 'with save_to option' do
      it 'saves to specified path', :integration do
        skip 'Requires live network connection'

        Tempfile.create(['test', '.xlsx']) do |tmp|
          path = extractor.download(save_to: tmp.path)

          expect(path).to eq(tmp.path)
          expect(File.exist?(path)).to be true
        end
      end
    end
  end

  describe '#fetch', :vcr do
    it 'downloads and parses the Foreign User List', :integration do
      skip 'Requires live network connection'

      list = extractor.fetch

      expect(list).to be_a(Ammitto::Data::Japan::Meti::ForeignUserList)
      expect(list.entities.count).to be > 0
      expect(list.source_file).to match(/\.xlsx$/)
      expect(list.source_url).to match(/meti\.go\.jp/)
    end
  end
end
