# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/au'

RSpec.describe Ammitto::Sources::Au::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :au' do
      expect(transformer.source_code).to eq(:au)
    end
  end

  describe '#authority' do
    it 'returns AU authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('au')
      expect(auth.name).to eq('Australia (DFAT)')
    end
  end

  # data-au stores the control date ISO; DFAT's own sheet writes it m/d/y.
  describe 'the control date as listed date' do
    include_context 'with parse failure log capture'

    let(:listed_for) do
      lambda do |value|
        transformer.send(:create_period, source: :au,
                                         listed_date: transformer.send(:parse_control_date, value)).listed_date
      end
    end
    let(:parse_unreadable) { -> { listed_for.call('garbage') } }
    let(:raise_unreadable) { -> { listed_for.call('13/40/24') } }

    it 'reads the ISO date data-au stores' do
      expect(listed_for.call('2024-02-23')).to eq(Date.new(2024, 2, 23))
    end

    it "reads DFAT's month-first date" do
      expect(listed_for.call('2/23/24')).to eq(Date.new(2024, 2, 23))
    end

    it 'reads a four-digit month-first year as written' do
      expect(listed_for.call('6/18/2025')).to eq(Date.new(2025, 6, 18))
    end

    # No plausibility floor: a four-digit year, or an ISO date, is published as
    # the source wrote it, however early. Read proleptic Gregorian: the
    # default Date::ITALY has no 10/10/1582 and would report it.
    {
      '2/3/0001' => Date.new(1, 2, 3, Date::GREGORIAN),
      '2/3/0099' => Date.new(99, 2, 3, Date::GREGORIAN),
      '2/3/0000' => Date.new(0, 2, 3, Date::GREGORIAN),
      '2/3/1899' => Date.new(1899, 2, 3),
      '0001-01-01' => Date.new(1, 1, 1, Date::GREGORIAN),
      '1899-12-31' => Date.new(1899, 12, 31),
      '10/10/1582' => Date.new(1582, 10, 10, Date::GREGORIAN),
      '1582-10-10' => Date.new(1582, 10, 10, Date::GREGORIAN)
    }.each do |value, date|
      it "publishes #{value.inspect} as written, without a report" do
        expect(count_parse_failures { listed_for.call(value) }).to eq(date)
        expect(run.count(:au)).to eq(0)
      end
    end

    it 'publishes no date, and reports nothing, when there is none' do
      expect(count_parse_failures { listed_for.call('') }).to be_nil
      expect(run.count(:au)).to eq(0)
    end

    it_behaves_like 'a reported parse failure', source: :au, field: :listed_date,
                                                raised_value: '13/40/24'

    # Date.parse would read each of the first four as a date; none is a shape
    # DFAT or data-au writes. '2/3/024' has a year that is not two or four
    # digits, and '2024-02-30' is not a calendar date.
    ['2/3', '23 Feb', '02-03-2024', '2024-2-3', '2/3/024', '2024-02-30', '2/30/24'].each do |value|
      it "reports #{value.inspect} once and publishes no date" do
        expect(count_parse_failures { listed_for.call(value) }).to be_nil
        expect(run.count(:au)).to eq(1)
      end
    end
  end

  describe '#transform' do
    # Driven through the legacy `Ammitto::Transformers::AuTransformer` alias so
    # the constant keeps its only coverage after this class gained its own file.
    let(:transformer) { Ammitto::Transformers::AuTransformer.new }

    context 'when transforming an individual' do
      let(:individual) do
        Ammitto::Sources::Au::Individual.new(
          reference: '8577',
          names: [
            Ammitto::Sources::Au::Name.new(
              text: 'Mohammad Salah JOKAR',
              name_type: Ammitto::Sources::Au::NameType::PRIMARY,
              script: 'Latn'
            ),
            Ammitto::Sources::Au::Name.new(
              text: 'محمد صالح جوکار',
              name_type: Ammitto::Sources::Au::NameType::ORIGINAL_SCRIPT,
              script: 'Arab'
            )
          ],
          dates_of_birth: [Ammitto::Sources::Au::FlexibleDate.parse('5 May 1957')],
          places_of_birth: [Ammitto::Sources::Au::Location.parse('Yazd, Iran')],
          citizenships: ['Iranian'],
          sanction: Ammitto::Sources::Au::Sanction.new(
            committees: 'Autonomous (Iran)',
            control_date: '2/2/26',
            instrument: 'Amendment Instrument 2026',
            targeted_financial_sanction: true,
            travel_ban: true,
            arms_embargo: false,
            maritime_restriction: false
          )
        )
      end

      subject(:result) { transformer.transform(individual) }

      it 'returns PersonEntity' do
        expect(result[:entity]).to be_a(Ammitto::PersonEntity)
      end

      it 'returns SanctionEntry' do
        expect(result[:entry]).to be_a(Ammitto::SanctionEntry)
      end

      it 'generates correct entity ID' do
        expect(result[:entity].id).to eq('https://www.ammitto.org/entity/au/8577')
      end

      it 'has correct number of name variants' do
        expect(result[:entity].names.size).to eq(2)
      end

      it 'has correct effects' do
        effect_types = result[:entry].effects.map(&:effect_type)
        expect(effect_types).to contain_exactly('asset_freeze', 'travel_ban')
      end

      it 'carries the complete birth date with its year' do
        birth = result[:entity].birth_info.first
        expect(birth.date).to eq(Date.new(1957, 5, 5))
        expect(birth.year).to eq(1957)
      end
    end

    # The birth-precision invariant: a source-provided year is
    # BirthInfo#year; BirthInfo#date is set only when the source states a
    # complete day-month-year.
    context 'when transforming partial birth dates' do
      def birth_infos_for(*raw_dates)
        individual = Ammitto::Sources::Au::Individual.new(
          reference: '9001',
          dates_of_birth: raw_dates.map do |raw|
            Ammitto::Sources::Au::FlexibleDate.parse(raw)
          end,
          places_of_birth: []
        )
        transformer.send(:transform_birth_info, individual)
      end

      it 'keeps a year-only date as year, without a date' do
        birth = birth_infos_for('1957').first
        expect(birth.year).to eq(1957)
        expect(birth.date).to be_nil
      end

      it 'keeps a month-year date as year, without inventing a day' do
        birth = birth_infos_for('May 1957').first
        expect(birth.year).to eq(1957)
        expect(birth.date).to be_nil
      end

      it 'keeps a circa year as a circa-flagged year, without a date' do
        birth = birth_infos_for('circa 1957').first
        expect(birth.year).to eq(1957)
        expect(birth.date).to be_nil
        expect(birth.circa).to be true
      end

      it 'resolves a fully stated date to a date plus year' do
        birth = birth_infos_for('5 May 1957').first
        expect(birth.date).to eq(Date.new(1957, 5, 5))
        expect(birth.year).to eq(1957)
      end
    end

    it 'turns a multi-year source cell into multiple BirthInfo records' do
      individual = Ammitto::Sources::Au::Individual.new(
        reference: 'multi-year',
        dates_of_birth: [],
        places_of_birth: []
      )
      individual.merge_row(
        'Date of Birth' => 'a) 4/04/1964 b) 1966'
      )

      births = transformer.send(:transform_birth_info, individual)

      expect(births.map(&:year)).to eq([1964, 1966])
      expect(births.map(&:circa)).to eq([false, false])
    end

    # DFAT states a span of years in one shape, and it is the only
    # multi-year date-of-birth value in the corpus (record au-8824).
    # The transformer used to publish 1959 as THE birth year.
    context 'when transforming a stated span of years' do
      def birth_for(raw)
        individual = Ammitto::Sources::Au::Individual.new(
          reference: '8824',
          dates_of_birth: [Ammitto::Sources::Au::FlexibleDate.parse(raw)],
          places_of_birth: []
        )
        transformer.send(:transform_birth_info, individual).first
      end

      it 'carries both bounds through and claims no year or date' do
        birth = birth_for('Approximately: Between 1959 and 1965')

        expect(birth.year_range_from).to eq(1959)
        expect(birth.year_range_to).to eq(1965)
        expect(birth.year).to be_nil
        expect(birth.date).to be_nil
      end

      it 'marks the "Approximately" span circa' do
        expect(birth_for('Approximately: Between 1959 and 1965').circa).to be true
      end

      # A span is not approximate by itself; without the source's own
      # marker it states its bounds exactly.
      it 'leaves a span without the marker un-circa' do
        birth = birth_for('Between 1959 and 1965')

        expect(birth.year_range_from).to eq(1959)
        expect(birth.circa).to be false
      end
    end

    context 'when transforming a vessel' do
      let(:vessel) do
        Ammitto::Sources::Au::Vessel.new(
          reference: '8230',
          names: [
            Ammitto::Sources::Au::Name.new(
              text: 'MOCHA',
              name_type: Ammitto::Sources::Au::NameType::PRIMARY,
              script: 'Latn'
            )
          ],
          imo_number: '9271951',
          previous_names: ['FACCA'],
          sanction: Ammitto::Sources::Au::Sanction.new(
            committees: 'Autonomous (Vessels)',
            control_date: '6/18/25',
            instrument: 'Vessel Designation 2025',
            targeted_financial_sanction: false,
            travel_ban: false,
            arms_embargo: false,
            maritime_restriction: true
          )
        )
      end

      subject(:result) { transformer.transform(vessel) }

      it 'returns VesselEntity' do
        expect(result[:entity]).to be_a(Ammitto::VesselEntity)
      end

      it 'has IMO number' do
        expect(result[:entity].imo_number).to eq('9271951')
      end

      it 'has maritime restriction effect' do
        effect_types = result[:entry].effects.map(&:effect_type)
        expect(effect_types).to include('sectoral_sanction')
      end

      it 'includes previous names as aliases' do
        expect(result[:entity].names.size).to eq(2)
      end
    end
  end
end
