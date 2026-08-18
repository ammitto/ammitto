# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/scrapers/ru/stop_list_page'

# Fixtures are trimmed from archived captures of the real pages
# (mid.ru/ru/maps/us/1814243/ and .../ca/1811224/). Every row that
# survives the trim is one the full corpus actually contains — the
# awkward ones were kept deliberately, since they are what a parser
# built against one tidy page gets wrong.
RSpec.describe Ammitto::Scrapers::Ru::StopListPage do
  def fixture(name)
    File.read(
      File.expand_path("../../../fixtures/ru/#{name}", __dir__),
      encoding: 'utf-8'
    )
  end

  def page(name, code)
    described_class.new(
      fixture(name),
      country_code: code,
      source_url: "https://mid.ru/ru/maps/#{code}/1/"
    )
  end

  let(:us) { page('us-stop-list.html', 'us') }
  let(:ca) { page('ca-stop-list.html', 'ca') }
  let(:us_row_count) { data_row_count('us-stop-list.html') }
  let(:ca_row_count) { data_row_count('ca-stop-list.html') }

  # Counted from the fixture rather than written down, so trimming a
  # fixture can never silently weaken the expectation.
  def data_row_count(name)
    Nokogiri::HTML(fixture(name)).css('table tr').count do |tr|
      cells = tr.css('td')
      cells.length == 4 && cells.none? { |c| c['colspan'] || c['rowspan'] }
    end
  end

  describe '#stop_list?' do
    it 'recognises a real stop-list page' do
      expect(us).to be_stop_list
      expect(ca).to be_stop_list
    end

    it 'rejects a country article that merely has a four-column table' do
      html = <<~HTML
        <html><body><h1>Канада</h1>
        <table><tr><td></td><td>Что-то (Something)</td><td>&ndash;</td>
        <td>текст</td></tr></table></body></html>
      HTML
      article = described_class.new(html, country_code: 'ca', source_url: 'x')

      expect(article).not_to be_stop_list
    end

    it 'rejects an interstitial carrying no table at all' do
      challenge = described_class.new(
        '<html><body>Data processing... Please, wait.</body></html>',
        country_code: 'us', source_url: 'x'
      )

      expect(challenge).not_to be_stop_list
      expect(challenge.entities).to be_empty
    end
  end

  describe '#heading' do
    # The country name is the first h1 on the page; only the second
    # says what the page is. Reading the first would call every country
    # article a stop list.
    it 'returns the heading naming the subject, not the country' do
      expect(us.heading).to include('персональными санкциями')
      expect(ca.heading).to include('персональными санкциями')
    end
  end

  describe '#entities' do
    it 'skips the alphabetical divider rows the US page carries' do
      # Dividers are single full-width cells. None may become an
      # entity, and every entity must carry at least one name — the
      # corpus has rows with only a Cyrillic form and rows with only a
      # Latin one, but never neither.
      expect(us.entities).to all(
        satisfy { |e| e['russian_name'] || e['english_name'] }
      )
      expect(us.entities.length).to eq(us_row_count)
    end

    it 'parses a page with no divider rows at all' do
      # Canada publishes the same list without the alphabet headings,
      # so a fixed skip count would drop real people here.
      expect(ca.entities).to all(
        satisfy { |e| e['russian_name'] || e['english_name'] }
      )
      expect(ca.entities.length).to eq(ca_row_count)
    end

    it 'splits the two names on the bracket' do
      entity = us.entities.find { |e| e['english_name'] == 'Ralph Lee Abraham Jr.' }

      expect(entity['russian_name']).to eq('Ральф АБРАХАМ')
      expect(entity['entity_type']).to eq('person')
      expect(entity['list_type']).to eq('stop_list')
    end

    it 'keeps a Cyrillic-only name rather than discarding the row' do
      # OpenSanctions' crawler asserts a bracket is present and would
      # raise on this row.
      entity = us.entities.find { |e| e['russian_name'] == 'Шанг Юн БЭЙ' }

      expect(entity).not_to be_nil
      expect(entity['english_name']).to be_nil
    end

    it 'recovers a name whose opening bracket is missing' do
      entity = ca.entities.find { |e| e['english_name'] == 'Jenica Atwin' }

      expect(entity['russian_name']).to eq('Дженика Этвин')
    end

    it 'keeps a bracket that belongs to the Latin name' do
      entity = ca.entities.find { |e| e['russian_name'] == 'Орися Сушко' }

      expect(entity['english_name']).to eq('Orysia (Irene) Sushko')
    end

    it 'does not split a surname carrying a Latin homoglyph' do
      # The source spells this with a Latin C inside an otherwise
      # Cyrillic surname. Splitting on the first Latin character cut it
      # in half.
      entity = us.entities.find { |e| e['english_name'] == 'John Anthony Barrasso' }

      expect(entity['russian_name']).to eq('Джон БАРРАСCО')
    end

    it 'strips the trailing semicolon Canada appends to each position' do
      expect(ca.entities.map { |e| e['title'] }).to all(satisfy { |t| !t.end_with?(';') })
    end

    it 'carries the country and source url onto every record' do
      expect(ca.entities).to all(include('country' => 'ca'))
      expect(ca.entities).to all(include('source_url' => 'https://mid.ru/ru/maps/ca/1/'))
    end
  end

  describe 'soft hyphens' do
    # A soft hyphen is an invisible line-break hint inside a word.
    # Spacing it apart splits one name into two.
    it 'removes them without splitting the name' do
      html = <<~HTML
        <html><body><h1>X</h1><h1>персональными санкциями</h1><table><tr>
        <td></td><td>Анна­Мария ПЕТРОВА (Anna­Maria Petrova)</td>
        <td>&ndash;</td><td>депутат</td></tr></table></body></html>
      HTML
      entity = described_class.new(html, country_code: 'xx', source_url: 'x')
                              .entities.first

      expect(entity['russian_name']).to eq('АннаМария ПЕТРОВА')
      expect(entity['english_name']).to eq('AnnaMaria Petrova')
    end
  end

  describe 'table selection' do
    # A page-wide `table tr` sweep merged a layout table into the list
    # and read nested cells as if they were the outer row's.
    it 'reads the list table and ignores an unrelated one beside it' do
      html = <<~HTML
        <html><body><h1>X</h1><h1>персональными санкциями</h1>
        <table><tr><td>a</td><td>b</td><td>c</td><td>d</td></tr></table>
        <table>
          <tr><td></td><td>Иван ПЕТРОВ (Ivan Petrov)</td><td>&ndash;</td><td>депутат</td></tr>
          <tr><td></td><td>Пётр ИВАНОВ (Pyotr Ivanov)</td><td>&ndash;</td><td>сенатор</td></tr>
        </table></body></html>
      HTML
      names = described_class.new(html, country_code: 'xx', source_url: 'x')
                             .entities.map { |e| e['english_name'] }

      expect(names).to eq(['Ivan Petrov', 'Pyotr Ivanov'])
    end
  end
end
