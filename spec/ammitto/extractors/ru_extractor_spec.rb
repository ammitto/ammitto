# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/extractors/ru_extractor'
require 'ammitto/scrapers/ru/ru_sanctions_scraper'

RSpec.describe Ammitto::Extractors::RuExtractor do
  subject(:extractor) { described_class.new }

  def stub_scrape(result)
    scraper = instance_double(Ammitto::Scrapers::Ru::RuSanctionsScraper,
                              fetch_all: result)
    allow(Ammitto::Scrapers::Ru::RuSanctionsScraper)
      .to receive(:new).and_return(scraper)
  end

  describe '#fetch' do
    it 'raises on a zero-entity scrape instead of reporting success' do
      # The stop-list is never legitimately empty: zero entities means
      # the site is blocked (mid.ru serves a JS anti-bot challenge) or
      # restructured. This used to flow through as a green run.
      stub_scrape({ announcements: [], entities: [], errors: [] })

      expect { extractor.fetch }
        .to raise_error(RuntimeError, /zero entities/)
    end

    it 'raises when the scraper collected errors instead of dropping them' do
      # RuSanctionsScraper#fetch_mid_data rescues into an errors array
      # that no caller ever read; a dead mid.ru was indistinguishable
      # from an empty list.
      stub_scrape({ announcements: [], entities: [],
                    errors: [{ source: 'mid', error: 'connection refused' }] })

      expect { extractor.fetch }
        .to raise_error(RuntimeError, /mid: connection refused/)
    end

    it 'returns the scraped data when entities were actually yielded' do
      data = { announcements: [{ list_type: 'stop_list' }],
               entities: [{ russian_name: 'Иванов Иван',
                            english_name: 'Ivanov Ivan',
                            entity_type: 'person' }],
               errors: [] }
      stub_scrape(data)

      expect(extractor.fetch).to eq(data)
    end
  end

  describe '#run' do
    it 'turns a zero-entity scrape into status :error' do
      # BaseExtractor#run converts the raise into the error result that
      # fails the fetch CLI's exit status (exit honesty).
      stub_scrape({ announcements: [], entities: [], errors: [] })

      result = extractor.run

      expect(result[:status]).to eq(:error)
      expect(result[:error]).to match(/zero entities/)
    end
  end
end
