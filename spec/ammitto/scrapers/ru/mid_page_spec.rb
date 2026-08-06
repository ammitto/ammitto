# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/scrapers/ru/mid_page'

RSpec.describe Ammitto::Scrapers::Ru::MidPage do
  subject(:page) { described_class.new }

  let(:agent) { instance_double(Mechanize) }

  before { page.instance_variable_set(:@agent, agent) }

  describe '#fetch_all_announcements' do
    it 'raises when the index page could not be fetched' do
      # BasePage#fetch swallows network errors into a nil page, and
      # #parse degrades nil to []. An unreachable mid.ru was therefore
      # indistinguishable from a site with no announcements, and the
      # pipeline reported success on it.
      allow(agent).to receive(:get).and_raise(SocketError, 'unreachable')

      expect { page.fetch_all_announcements }
        .to raise_error(RuntimeError, /failed to fetch/)
    end

    it 'parses the fetched page instead of raising when the fetch worked' do
      html = <<~HTML
        <html><body>
          <a href="/ru/foreign_policy/news/1234/">
            Заявление МИД России о персональных санкциях
          </a>
        </body></html>
      HTML
      index_page = Mechanize::Page.new(
        URI('https://www.mid.ru/ru/foreign_policy/news/'),
        nil, html, 200, Mechanize.new
      )
      allow(agent).to receive(:get)
        .with(described_class::NEWS_URL).and_return(index_page)
      # The detail-page fetch failing is tolerated per announcement; only
      # the index-page fetch contract is under test here.
      allow(agent).to receive(:get)
        .with('https://www.mid.ru/ru/foreign_policy/news/1234/')
        .and_raise(SocketError, 'detail unreachable')

      expect(page.fetch_all_announcements).to eq([])
    end
  end
end
