# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/au'

RSpec.describe Ammitto::Sources::Au::SanctionsList do
  let(:sample_csv) do
    <<~CSV
      Reference,Name of Individual or Entity,Type,Name Type,Alias Strength,Date of Birth,Place of Birth,Citizenship,Address,Additional Information,Listing Information,IMO Number,Committees,Control Date,Instrument of Designation,Targeted Financial Sanction,Travel Ban,Arms Embargo,Maritime Restriction
      8577,Mohammad Salah JOKAR,Individual,Primary Name,,5 May 1957,Yazd,Iranian,,General of the Islamic Revolutionary Guards Corps,Autonomous Sanctions List 2012,,Autonomous (Iran),2/2/26,Amendment Instrument 2026,TRUE,TRUE,FALSE,FALSE
      8577a,محمد صالح جوکار,Individual,Original Script,,5 May 1957,Yazd,Iranian,,General of the Islamic Revolutionary Guards Corps,Autonomous Sanctions List 2012,,Autonomous (Iran),2/2/26,Amendment Instrument 2026,TRUE,TRUE,FALSE,FALSE
      8577b,Mohammad Saleh JOKAR,Individual,Alias,Strong,5 May 1957,Yazd,Iranian,,General of the Islamic Revolutionary Guards Corps,Autonomous Sanctions List 2012,,Autonomous (Iran),2/2/26,Amendment Instrument 2026,TRUE,TRUE,FALSE,FALSE
      8556,SAFETY EQUIPMENT PROCUREMENT (SEP),Entity,Primary Name,,,,,,IRe.060. Designation: AIO front-company,Listed by 1737 Committee,,1737 (Iran),12/12/25,Charter Regulations 2025,TRUE,FALSE,FALSE,FALSE
      8230,MOCHA,Vessel,Primary Name,,,,,,Previous names include FACCA,Designated as sanctioned vessel,9271951,Autonomous (Vessels),6/18/25,Vessel Designation 2025,FALSE,FALSE,FALSE,TRUE
    CSV
  end

  describe '.from_csv' do
    subject(:list) { described_class.from_csv(sample_csv) }

    it 'parses individuals correctly' do
      expect(list.individuals.size).to eq(1)
    end

    it 'parses organizations correctly' do
      expect(list.organizations.size).to eq(1)
    end

    it 'parses vessels correctly' do
      expect(list.vessels.size).to eq(1)
    end

    it 'returns correct total count' do
      expect(list.count).to eq(3)
    end

    context 'when parsing individual with multiple name variants' do
      let(:individual) { list.individuals.first }

      it 'has correct reference number' do
        expect(individual.reference).to eq('8577')
      end

      it 'merges all name variants' do
        expect(individual.names.size).to eq(3)
      end

      it 'has primary name' do
        expect(individual.primary_name).to eq('Mohammad Salah JOKAR')
      end

      it 'has Arabic name with correct script' do
        arabic_name = individual.names.find(&:original_script?)
        expect(arabic_name).not_to be_nil
        expect(arabic_name.script).to eq('Arab')
      end

      it 'has alias with strength' do
        alias_name = individual.names.find(&:alias?)
        expect(alias_name).not_to be_nil
        expect(alias_name.alias_strength).to eq('Strong')
      end

      it 'has citizenships' do
        expect(individual.citizenships).to include('Iranian')
      end

      it 'has sanction effects' do
        expect(individual.sanction.targeted_financial_sanction).to be true
        expect(individual.sanction.travel_ban).to be true
        expect(individual.sanction.arms_embargo).to be false
      end

      it 'has flexible dates of birth' do
        expect(individual.dates_of_birth).not_to be_empty
        expect(individual.dates_of_birth.first).to be_a(Ammitto::Sources::Au::FlexibleDate)
      end

      it 'extracts birth years' do
        expect(individual.birth_years).to include(1957)
      end
    end

    context 'when parsing organization' do
      let(:organization) { list.organizations.first }

      it 'has correct reference number' do
        expect(organization.reference).to eq('8556')
      end

      it 'has primary name' do
        expect(organization.primary_name).to eq('SAFETY EQUIPMENT PROCUREMENT (SEP)')
      end

      it 'has committees info in sanction' do
        expect(organization.sanction.committees).to eq('1737 (Iran)')
      end

      it 'has correct regime type' do
        expect(organization.sanction.regime_type).to eq(:un_security_council)
      end
    end

    context 'when parsing vessel' do
      let(:vessel) { list.vessels.first }

      it 'has correct reference number' do
        expect(vessel.reference).to eq('8230')
      end

      it 'has IMO number' do
        expect(vessel.imo_number).to eq('9271951')
      end

      it 'has primary name' do
        expect(vessel.primary_name).to eq('MOCHA')
      end

      it 'has maritime restriction effect' do
        expect(vessel.sanction.maritime_restriction).to be true
        expect(vessel.sanction.targeted_financial_sanction).to be false
      end

      it 'extracts previous names' do
        expect(vessel.previous_names).to include('FACCA')
      end
    end
  end

  describe '#count_by_regime' do
    subject(:list) { described_class.from_csv(sample_csv) }

    it 'counts entities by regime' do
      counts = list.count_by_regime
      expect(counts['Autonomous (Iran)']).to eq(1)
      expect(counts['1737 (Iran)']).to eq(1)
      expect(counts['Autonomous (Vessels)']).to eq(1)
    end
  end

  describe '#count_by_effect' do
    subject(:list) { described_class.from_csv(sample_csv) }

    it 'counts entities by effect type' do
      counts = list.count_by_effect
      expect(counts['targeted_financial_sanction']).to eq(2) # individual + org
      expect(counts['travel_ban']).to eq(1) # individual only
      expect(counts['maritime_restriction']).to eq(1) # vessel only
    end
  end
end
