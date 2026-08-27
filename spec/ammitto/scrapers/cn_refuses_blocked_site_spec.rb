# frozen_string_literal: true

require 'ammitto'
require 'mechanize'
require 'ammitto/scrapers/cn/mofcom_page'
require 'ammitto/scrapers/cn/mfa_page'
require 'ammitto/extractors/cn_extractor'
require 'ammitto/scrapers/cn/cn_sanctions_scraper'

# A blocked Chinese government site must not read as "China sanctions nobody".
#
# `BasePage#fetch` swallows a network error into a nil return. MofcomPage and
# MfaPage turned that nil into an empty array, the scraper collected no error,
# and the extractor reported {status: :success, entities: 0}. The RU twin of
# this bug was found and fixed — `MidPage#fetch_all_announcements` raises, and
# `RuExtractor` refuses both a non-empty error list and a zero-entity harvest.
# The CN path was left with neither guard.
RSpec.describe 'the CN scrape when the site cannot be read' do
  describe Ammitto::Scrapers::Cn::MofcomPage do
    it 'raises rather than returning no announcements' do
      page = described_class.new
      allow(page).to receive(:fetch).and_return(nil)

      expect { page.fetch_all_announcements }
        .to raise_error(Ammitto::NetworkError, /failed to fetch/)
    end
  end

  describe Ammitto::Scrapers::Cn::MfaPage do
    it 'raises rather than returning no announcements' do
      page = described_class.new
      allow(page).to receive(:fetch).and_return(nil)

      expect { page.fetch_all_announcements }
        .to raise_error(Ammitto::NetworkError, /failed to fetch/)
    end

    it 'keys on the fetch return value, not on a page left by an earlier fetch' do
      # fetch does not clear @page on failure, so stale content must not
      # mask a failed refetch.
      page = described_class.new
      page.instance_variable_set(:@page, Object.new)
      allow(page).to receive(:fetch).and_return(nil)

      expect { page.fetch_all_announcements }.to raise_error(Ammitto::NetworkError, /failed to fetch/)
    end
  end

  describe Ammitto::Extractors::CnExtractor do
    it 'refuses a harvest that collected errors' do
      extractor = described_class.new
      scraper = instance_double(
        Ammitto::Scrapers::Cn::CnSanctionsScraper,
        fetch_all: { entities: [], errors: [{ source: 'mofcom', error: '403' }] }
      )
      allow(Ammitto::Scrapers::Cn::CnSanctionsScraper).to receive(:new).and_return(scraper)

      expect { extractor.send(:fetch_from_web) }
        .to raise_error(Ammitto::Error, /cn scrape failed.*403/m)
    end

    it 'refuses a harvest that yielded no entities at all' do
      extractor = described_class.new
      scraper = instance_double(
        Ammitto::Scrapers::Cn::CnSanctionsScraper,
        fetch_all: { entities: [], errors: [] }
      )
      allow(Ammitto::Scrapers::Cn::CnSanctionsScraper).to receive(:new).and_return(scraper)

      expect { extractor.send(:fetch_from_web) }
        .to raise_error(Ammitto::ParseError, /zero entities/)
    end
  end

  # A detail page that failed is data we did not read. One working
  # announcement alongside failures used to produce a non-empty harvest
  # and an empty error list, which the extractor accepted as success.
  #
  # These drive the real fetch. An earlier version of this spec injected
  # an already-populated detail_errors array, which passed while the
  # actual failure path still dropped everything on the floor.
  describe 'partial detail-page failures' do
    it 'MfaPage records a detail page it could not fetch' do
      page = Ammitto::Scrapers::Cn::MfaPage.new
      agent = instance_double(Mechanize)
      page.instance_variable_set(:@agent, agent)
      page.instance_variable_set(:@page, :an_index_page)
      allow(page).to receive(:find_announcement_links).and_return(
        [{ url: 'https://x/good' }, { url: 'https://x/dead' }]
      )
      allow(agent).to receive(:get).with('https://x/good').and_return(:ok)
      allow(agent).to receive(:get).with('https://x/dead').and_raise('timeout')
      allow(page).to receive(:parse_announcement_detail)
        .and_return({ title: 'one', entities: [] })

      page.parse

      expect(page.detail_errors.map { |e| e[:url] }).to eq(['https://x/dead'])
    end

    it 'MofcomPage records one too' do
      page = Ammitto::Scrapers::Cn::MofcomPage.new
      agent = instance_double(Mechanize)
      page.instance_variable_set(:@agent, agent)
      allow(page).to receive_messages(
        fetch: :an_index_page,
        find_announcement_links: [{ url: 'https://y/good' }, { url: 'https://y/dead' }],
        parse_announcement_detail: { title: 'one', entities: [] }
      )
      allow(agent).to receive(:get).with('https://y/good').and_return(:ok)
      allow(agent).to receive(:get).with('https://y/dead').and_raise('refused')

      page.fetch_all_announcements

      expect(page.detail_errors.map { |e| e[:url] }).to eq(['https://y/dead'])
    end

    it 'the scraper turns a recorded detail failure into an error' do
      page = Ammitto::Scrapers::Cn::MfaPage.new
      allow(page).to receive_messages(
        fetch_all_announcements: [{ title: 'one', entities: [] }],
        detail_errors: [{ url: 'https://x/dead', error: 'timeout' }]
      )
      allow(Ammitto::Scrapers::Cn::MfaPage).to receive(:new).and_return(page)

      result = Ammitto::Scrapers::Cn::CnSanctionsScraper.new.fetch_mfa_data

      expect(result[:errors].map { |e| e[:error] }).to include(/timeout/)
    end
  end

  # The aggregate is heterogeneous: the scraper's boundaries rescue
  # StandardError, so a parse failure lands in the same list as a fetch
  # failure. Typing it NetworkError told a caller to retry when the page
  # structure may simply have changed.
  it 'does not call a parsing failure a network failure' do
    scraper = instance_double(
      Ammitto::Scrapers::Cn::CnSanctionsScraper,
      fetch_all: { announcements: [], entities: [],
                   errors: [{ source: 'mfa', error: 'bad html' }] }
    )
    allow(Ammitto::Scrapers::Cn::CnSanctionsScraper)
      .to receive(:new).and_return(scraper)

    # Assert the exact class, not "an Error but not a NetworkError".
    # `not_to raise_error(SpecificClass)` passes when a different error is
    # raised, which is the false positive RSpec warns about.
    error = begin
      Ammitto::Extractors::CnExtractor.new.fetch
      nil
    rescue Ammitto::Error => e
      e
    end

    expect(error.class).to eq(Ammitto::Error)
    expect(error.message).to match(/bad html/)
  end

  # The web route refused an empty harvest; the reference-docs route
  # returned straight past that check.
  describe 'the local reference-docs route' do
    it 'refuses an empty directory instead of reporting zero entities' do
      Dir.mktmpdir do |dir|
        extractor = Ammitto::Extractors::CnExtractor.new
        extractor.reference_docs_path = dir

        expect { extractor.fetch }
          .to raise_error(Ammitto::ParseError, /reference docs yielded zero entities/)
      end
    end
  end
end
