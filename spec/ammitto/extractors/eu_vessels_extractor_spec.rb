# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/extractors/eu_vessels_extractor'

module EuVesselsExtractorSpecHelpers
  def page(*hrefs)
    links = hrefs.map { |href| %(<a href="#{href}">list</a>) }.join
    "<html><body>#{links}</body></html>"
  end
end

RSpec.describe Ammitto::Extractors::EuVesselsExtractor do
  include EuVesselsExtractorSpecHelpers

  subject(:extractor) { described_class.new }

  let(:index_html) do
    File.read(File.expand_path('../../fixtures/eu_vessels/index.html', __dir__))
  end
  let(:client) { Ammitto::Extractors::HttpClient }

  describe '#xlsx_url' do
    it 'reads the workbook link from the index page' do
      allow(client).to receive(:get).and_return(index_html)

      expect(extractor.xlsx_url).to eq(
        'https://www.dma.dk/Media/639204765550435137/ImportversionListOfEUDesignatedVessels240726.xlsx'
      )
      expect(client).to have_received(:get).with(
        described_class::INDEX_URL, headers: { 'User-Agent' => 'Mozilla/5.0' }
      )
    end
  end

  describe '#xlsx_url_from' do
    it 'keeps an absolute href as given' do
      url = 'https://files.example.org/Media/1/List.XLSX'

      expect(extractor.xlsx_url_from(page(url))).to eq(url)
    end

    it 'treats repeated links to one workbook as one' do
      html = page('/Media/1/List.xlsx', 'https://www.dma.dk/Media/1/List.xlsx')

      expect(extractor.xlsx_url_from(html)).to eq('https://www.dma.dk/Media/1/List.xlsx')
    end

    it 'treats links differing only by fragment as one workbook' do
      html = page('/Media/1/List.xlsx#top', '/Media/1/List.xlsx#sheet2')

      expect(extractor.xlsx_url_from(html)).to eq('https://www.dma.dk/Media/1/List.xlsx')
    end

    it 'refuses a workbook not offered over https, naming the index page' do
      html = page('ftp://ftp.dma.dk/Media/1/List.xlsx')

      expect { extractor.xlsx_url_from(html) }.to raise_error(
        Ammitto::ParseError,
        %r{#{Regexp.escape(described_class::INDEX_URL)}, found 1: ftp://ftp\.dma\.dk/Media/1/List\.xlsx}
      )
    end

    it 'names the index page when no workbook is linked' do
      html = index_html.gsub(/<a [^>]*\.xlsx"[^>]*>/, '<a href="/Media/2/List.csv">')

      expect { extractor.xlsx_url_from(html) }.to raise_error(
        Ammitto::ParseError, /one https \.xlsx link on #{Regexp.escape(described_class::INDEX_URL)}, found 0/
      )
    end

    it 'refuses to choose between two workbooks' do
      html = page('/Media/1/A.xlsx', '/Media/2/B.xlsx')

      expect { extractor.xlsx_url_from(html) }.to raise_error(
        Ammitto::ParseError, %r{found 2: https://www\.dma\.dk/Media/1/A\.xlsx, https://www\.dma\.dk/Media/2/B\.xlsx}
      )
    end
  end

  describe '#fetch' do
    # The fixture's workbook URL appears nowhere in lib/, so only discovery
    # from the index page can produce it.
    let(:discovered) do
      'https://www.dma.dk/Media/639204765550435137/ImportversionListOfEUDesignatedVessels240726.xlsx'
    end

    it 'downloads the workbook the index page links' do
      allow(client).to receive(:get).with(described_class::INDEX_URL, anything).and_return(index_html)
      allow(client).to receive(:get).with(discovered, anything).and_return('PK')

      path = extractor.fetch

      expect(File.binread(path)).to eq('PK')
      expect(client).to have_received(:get).with(described_class::INDEX_URL, anything).ordered
      expect(client).to have_received(:get).with(discovered, anything).ordered
    ensure
      extractor.cleanup
    end
  end

  it 'reports the index page as its endpoint without a request' do
    allow(client).to receive(:get)

    expect(extractor.api_endpoint).to eq(described_class::INDEX_URL)
    expect(client).not_to have_received(:get)
  end
end
