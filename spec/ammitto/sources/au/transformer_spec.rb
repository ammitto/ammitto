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
