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

    it 'raises on a failed refetch even when an earlier fetch left a page' do
      # BasePage#fetch keeps @page on failure, so the raise keys on the
      # fetch return value, not the ivar: a stale page from an earlier
      # successful fetch must not mask a dead site with stale content.
      page.instance_variable_set(:@page, instance_double(Mechanize::Page))
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
      # A failed detail page no longer raises, but it is recorded in
      # #detail_errors instead of being silently omitted. The log line
      # stays behind verbose?, like the cn scrapers' per-link logs, so
      # a normal run emits nothing to stderr.
      allow(agent).to receive(:get)
        .with('https://www.mid.ru/ru/foreign_policy/news/1234/')
        .and_raise(SocketError, 'detail unreachable')

      announcements = nil
      expect { announcements = page.fetch_all_announcements }
        .not_to output.to_stderr

      expect(announcements).to eq([])
      expect(page.detail_errors.length).to eq(1)
    end

    it 'collects failed detail pages so one success is not full success' do
      # One successful detail page next to a failing one used to return
      # only the successful announcement with no trace of the failure,
      # so the extractor reported success with partial data.
      index_html = <<~HTML
        <html><body>
          <a href="/ru/foreign_policy/news/1/">
            Заявление МИД России о санкциях против граждан США
          </a>
          <a href="/ru/foreign_policy/news/2/">
            Заявление МИД России о санкциях против политиков
          </a>
        </body></html>
      HTML
      detail_html = <<~HTML
        <html><body><article>
          <h1>Заявление МИД России</h1>
          1. Иванов Иван Иванович (Ivanov Ivan) – директор института.
        </article></body></html>
      HTML
      index_page = Mechanize::Page.new(
        URI('https://www.mid.ru/ru/foreign_policy/news/'),
        nil, index_html, 200, Mechanize.new
      )
      detail_page = Mechanize::Page.new(
        URI('https://www.mid.ru/ru/foreign_policy/news/1/'),
        nil, detail_html, 200, Mechanize.new
      )
      allow(agent).to receive(:get)
        .with(described_class::NEWS_URL).and_return(index_page)
      allow(agent).to receive(:get)
        .with('https://www.mid.ru/ru/foreign_policy/news/1/')
        .and_return(detail_page)
      allow(agent).to receive(:get)
        .with('https://www.mid.ru/ru/foreign_policy/news/2/')
        .and_raise(SocketError, 'boom')

      announcements = page.fetch_all_announcements

      expect(announcements.length).to eq(1)
      expect(announcements.first[:source_url])
        .to eq('https://www.mid.ru/ru/foreign_policy/news/1/')
      expect(announcements.first[:entities].length).to eq(1)
      expect(page.detail_errors).to eq(
        [{ url: 'https://www.mid.ru/ru/foreign_policy/news/2/',
           error: 'boom' }]
      )
    end

    it 'logs per-detail failures only in verbose mode' do
      html = <<~HTML
        <html><body>
          <a href="/ru/foreign_policy/news/9/">
            Заявление МИД России о персональных санкциях
          </a>
        </body></html>
      HTML
      index_page = Mechanize::Page.new(
        URI('https://www.mid.ru/ru/foreign_policy/news/'),
        nil, html, 200, Mechanize.new
      )
      verbose_page = described_class.new(verbose: true)
      verbose_page.instance_variable_set(:@agent, agent)
      allow(agent).to receive(:get)
        .with(described_class::NEWS_URL).and_return(index_page)
      allow(agent).to receive(:get)
        .with('https://www.mid.ru/ru/foreign_policy/news/9/')
        .and_raise(SocketError, 'boom')

      expect { verbose_page.fetch_all_announcements }
        .to output(%r{Error parsing .*news/9}).to_stdout

      expect(verbose_page.detail_errors.length).to eq(1)
    end
  end
end
