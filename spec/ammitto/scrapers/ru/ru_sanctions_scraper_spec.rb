# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/scrapers/ru/ru_sanctions_scraper'

RSpec.describe Ammitto::Scrapers::Ru::RuSanctionsScraper do
  subject(:scraper) { described_class.new }

  describe '#fetch_all' do
    it 'propagates detail-page failures into the returned errors' do
      # One successful announcement next to a failed detail page used
      # to come back with empty errors, so RuExtractor (which raises on
      # non-empty errors) reported success on partial data.
      announcement = {
        list_type: 'stop_list',
        source_url: 'https://www.mid.ru/ru/foreign_policy/news/1/',
        entities: [{ russian_name: 'Иванов Иван',
                     english_name: 'Ivanov Ivan',
                     entity_type: 'person' }]
      }
      mid_page = instance_double(
        Ammitto::Scrapers::Ru::MidPage,
        fetch_all_announcements: [announcement],
        detail_errors: [{ url: 'https://www.mid.ru/ru/foreign_policy/news/2/',
                          error: 'boom' }]
      )
      allow(Ammitto::Scrapers::Ru::MidPage)
        .to receive(:new).and_return(mid_page)

      result = scraper.fetch_all

      expect(result[:announcements].length).to eq(1)
      expect(result[:entities].length).to eq(1)
      expect(result[:errors]).to eq(
        [{ source: 'mid',
           error: 'https://www.mid.ru/ru/foreign_policy/news/2/: boom' }]
      )
    end

    it 'returns empty errors when every detail page parsed' do
      mid_page = instance_double(
        Ammitto::Scrapers::Ru::MidPage,
        fetch_all_announcements: [],
        detail_errors: []
      )
      allow(Ammitto::Scrapers::Ru::MidPage)
        .to receive(:new).and_return(mid_page)

      expect(scraper.fetch_all[:errors]).to eq([])
    end
  end
end
