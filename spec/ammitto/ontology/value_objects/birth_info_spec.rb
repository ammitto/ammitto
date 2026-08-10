# frozen_string_literal: true

require 'ammitto'

RSpec.describe Ammitto::Ontology::ValueObjects::BirthInfo do
  describe '#birth_year' do
    it 'prefers the full date over the bare year' do
      info = described_class.new(date: Date.new(1964, 7, 17), year: 1999)
      expect(info.birth_year).to eq(1964)
    end

    it 'falls back to the bare year, then nil' do
      expect(described_class.new(year: 1964).birth_year).to eq(1964)
      expect(described_class.new.birth_year).to be_nil
    end
  end

  describe '#present?' do
    it 'counts date, year, city, region, or country' do
      expect(described_class.new(year: 1964)).to be_present
      expect(described_class.new(city: 'Bern')).to be_present
      expect(described_class.new(region: 'BE')).to be_present
      expect(described_class.new(circa: true)).not_to be_present
    end

    # A span is content. Counting only the scalars would drop a
    # range-only record from every consumer that gates on #present?.
    it 'counts either range bound on its own' do
      expect(described_class.new(year_range_from: 1953)).to be_present
      expect(described_class.new(year_range_to: 1958)).to be_present
    end
  end

  describe '#to_s' do
    it 'renders exact output with and without circa' do
      expect(described_class.new(year: 1964, circa: true).to_s).to eq('c. 1964')
      expect(described_class.new(year: 1964).to_s).to eq('1964')
    end

    it 'renders nothing for circa without a date, and region alone' do
      expect(described_class.new(circa: true).to_s).to eq('')
      expect(described_class.new(region: 'BE').to_s).to eq('BE')
    end

    it 'appends the place exactly, with no stray spacing' do
      info = described_class.new(date: Date.new(1964, 7, 17), city: 'Bern', country: 'CH')
      expect(info.to_s).to eq('1964-07-17 Bern, CH')
    end
  end

  describe '#to_hash' do
    it 'omits the default circa=false' do
      expect(described_class.new(year: 1964).to_hash).to eq({ year: 1964 })
    end

    it 'carries both bounds, and a lone bound alone' do
      span = described_class.new(year_range_from: 1959, year_range_to: 1965)
      expect(span.to_hash)
        .to eq({ year_range_from: 1959, year_range_to: 1965 })

      expect(described_class.new(year_range_to: 1980).to_hash)
        .to eq({ year_range_to: 1980 })
    end
  end

  describe 'year range display and serialization' do
    it 'renders a closed span, and an open one as its open direction' do
      expect(described_class.new(year_range_from: 1959, year_range_to: 1965).to_s)
        .to eq('1959-1965')
      expect(described_class.new(year_range_from: 1953).to_s)
        .to eq('1953 or later')
      expect(described_class.new(year_range_to: 1958).to_s)
        .to eq('no later than 1958')
    end

    it 'keeps circa independent of the span' do
      expect(described_class.new(year_range_from: 1953, year_range_to: 1958,
                                 circa: true).to_s)
        .to eq('c. 1953-1958')
      expect(described_class.new(year_range_from: 1960, year_range_to: 1962).to_s)
        .to eq('1960-1962')
    end

    it 'round-trips both bounds through YAML and JSON' do
      span = described_class.new(year_range_from: 1959, year_range_to: 1965)

      from_yaml = described_class.from_yaml(span.to_yaml)
      expect(from_yaml.year_range_from).to eq(1959)
      expect(from_yaml.year_range_to).to eq(1965)

      from_json = described_class.from_json(span.to_json)
      expect(from_json.year_range_from).to eq(1959)
      expect(from_json.year_range_to).to eq(1965)
    end

    # The Neo4j property list drives both import and export, so a name
    # missing from it is a field that never reaches the graph.
    it 'carries both bounds into the Neo4j properties' do
      span = described_class.new(year_range_from: 1959, year_range_to: 1965)

      expect(span.neo4j_properties)
        .to include(year_range_from: 1959, year_range_to: 1965)
    end
  end
end
