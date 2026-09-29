# frozen_string_literal: true

require 'date'
require 'ammitto'
require 'ammitto/sources/eu_vessels/transformer'

module EuVesselsTransformerSpecHelpers
  def vessel(name, imo, *rows)
    Ammitto::Sources::EuVessels::Vessel.new(
      vessel_name: name, imo_number: imo,
      designations: rows.map do |date, text|
        Ammitto::Sources::EuVessels::Designation.new(date_of_application: date, subject_to: text)
      end
    )
  end
end

RSpec.describe Ammitto::Sources::EuVessels::Transformer do
  include EuVesselsTransformerSpecHelpers

  let(:list) { 'https://www.ammitto.org/entry/eu_vessels/vessel-sanctions-list' }
  let(:hao_fan) do
    vessel('HAO FAN 6', '8628597',
           [Date.new(2017, 10, 3), 'Port entry ban (Council Regulation 2017/1509)'],
           [Date.new(2018, 3, 30), 'De-registration (Council Regulation 2017/1509)'])
  end

  it 'publishes one entity and one entry per designation' do
    results = described_class.new.transform(hao_fan)

    expect(results.map { |r| r[:entity].id }.uniq).to eq(['https://www.ammitto.org/entity/eu_vessels/8628597'])
    expect(results.map { |r| r[:entry].period.listed_date }).to eq([Date.new(2017, 10, 3), Date.new(2018, 3, 30)])
  end

  it 'keeps the bare IMO entry IRI for the earliest designation and suffixes later ones' do
    ids = described_class.new.transform(hao_fan).map { |r| r[:entry].id }

    expect(ids).to eq(["#{list}/8628597", "#{list}/8628597-2018-03-30-de-registration"])
  end

  it 'moves the bare IRI only when a designation dated before the earliest arrives' do
    later = vessel('Alpha', '9000001', [Date.new(2025, 5, 20), 'Article 3s (Council Regulation 833/2014)'],
                   [Date.new(2026, 1, 1), 'Article 3s (Council Regulation 833/2014)'])
    backdated = vessel('Alpha', '9000001', [Date.new(2024, 1, 1), 'Article 3s (Council Regulation 833/2014)'],
                       [Date.new(2025, 5, 20), 'Article 3s (Council Regulation 833/2014)'])
    by_date = lambda do |v|
      described_class.new.transform(v).to_h { |r| [r[:entry].period.listed_date, r[:entry].id] }
    end

    expect(by_date.call(later)[Date.new(2025, 5, 20)]).to eq("#{list}/9000001")
    expect(by_date.call(backdated)).to eq(
      Date.new(2024, 1, 1) => "#{list}/9000001",
      Date.new(2025, 5, 20) => "#{list}/9000001-2025-05-20-article-3s"
    )
  end

  it 'reads a file fetched before Subject to was recorded as a dated entry with no stated measure' do
    legacy = Ammitto::Sources::EuVessels::Vessel.from_hash(
      'vessel_name' => 'Mikhail Ulyanov', 'imo_number' => '9333670', 'date_of_application' => '2025-12-19'
    )

    entry = described_class.new.transform(legacy).first[:entry]

    expect(entry.id).to eq("#{list}/9333670")
    expect(entry.period.listed_date).to eq(Date.new(2025, 12, 19))
    expect([entry.regime, entry.effects, entry.legal_bases, entry.remarks]).to all(be_nil.or(be_empty))
  end

  it 'states each designation\'s own measure and remarks it verbatim' do
    entries = described_class.new.transform(hao_fan).map { |r| r[:entry] }

    expect(entries.map { |e| e.effects.map(&:effect_type) }).to eq([%w[entry_ban], %w[other]])
    expect(entries.last.remarks).to eq('De-registration (Council Regulation 2017/1509)')
  end

  it 'publishes an Article 3s vessel under the Russia regime without an asset freeze' do
    entry = described_class.new.transform(
      vessel('Alpha', '9000001', [Date.new(2025, 5, 20), 'Article 3s (Council Regulation 833/2014)'])
    ).first[:entry]

    expect(entry.regime.code).to eq('RUSSIA')
    expect(entry.legal_bases.map(&:identifier)).to eq(['Council Regulation (EU) No 833/2014'])
    expect(entry.effects.map(&:effect_type)).not_to include('asset_freeze')
  end

  it 'names a vessel without an IMO number after its name' do
    result = described_class.new.transform(
      vessel('MIN NING DE YOU 078', nil, [Date.new(2018, 3, 30), 'Port entry ban (Council Regulation 2017/1509)'])
    ).first

    expect(result[:entity].id).to eq('https://www.ammitto.org/entity/eu_vessels/min-ning-de-you-078')
    expect(result[:entry].id).to eq("#{list}/min-ning-de-you-078")
  end

  it 'gives the bare IRI to the earliest designation whatever order the file lists them in' do
    reversed = vessel('Alpha', '9000001', [Date.new(2026, 1, 1), 'Article 3s (Council Regulation 833/2014)'],
                      [Date.new(2025, 1, 1), 'Article 3s (Council Regulation 833/2014)'])

    ids = described_class.new.transform(reversed).to_h { |r| [r[:entry].period.listed_date, r[:entry].id] }

    expect(ids).to eq(
      Date.new(2025, 1, 1) => "#{list}/9000001",
      Date.new(2026, 1, 1) => "#{list}/9000001-2026-01-01-article-3s"
    )
  end

  it 'refuses a vessel whose later designation states no measure rather than crashing' do
    unstated = vessel('Alpha', '9000001', [Date.new(2025, 1, 1), 'Article 3s (Council Regulation 833/2014)'],
                      [Date.new(2026, 1, 1), nil])

    expect { described_class.new.transform(unstated) }
      .to raise_error(Ammitto::ParseError, /9000001.*Subject to/)
  end

  it 'refuses a vessel with no designations rather than publishing it bare' do
    expect { described_class.new.transform(vessel('Alpha', '9000001')) }
      .to raise_error(Ammitto::ParseError, /no designations/)
  end
end
