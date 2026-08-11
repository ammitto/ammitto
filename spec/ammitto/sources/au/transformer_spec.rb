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
