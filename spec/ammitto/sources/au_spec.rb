# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/au'

RSpec.describe Ammitto::Sources::Au do
  describe '.parse_base_reference' do
    it 'extracts base reference from plain number' do
      expect(described_class::BaseEntity.parse_base_reference('8577')).to eq('8577')
    end

    it 'extracts base reference with single letter suffix' do
      expect(described_class::BaseEntity.parse_base_reference('8577a')).to eq('8577')
    end

    it 'extracts base reference with multiple letter suffix' do
      expect(described_class::BaseEntity.parse_base_reference('8577bcd')).to eq('8577')
    end
  end
end

RSpec.describe Ammitto::Sources::Au::Script do
  describe '.detect' do
    it 'detects Latin script' do
      expect(described_class.detect('Mohammad Salah JOKAR')).to eq('Latn')
    end

    it 'detects Arabic script' do
      expect(described_class.detect('محمد صالح جوکار')).to eq('Arab')
    end

    it 'detects Cyrillic script' do
      expect(described_class.detect('Владимир ПУТИН')).to eq('Cyrl')
    end

    it 'detects Chinese script' do
      expect(described_class.detect('习近平')).to eq('Hani')
    end

    it 'returns Latn for empty string' do
      expect(described_class.detect('')).to eq('Latn')
    end

    it 'returns Latn for nil' do
      expect(described_class.detect(nil)).to eq('Latn')
    end
  end
end

RSpec.describe Ammitto::Sources::Au::Name do
  describe '#primary?' do
    it 'returns true for Primary Name' do
      name = described_class.new(
        text: 'Test',
        name_type: Ammitto::Sources::Au::NameType::PRIMARY,
        script: 'Latn'
      )
      expect(name.primary?).to be true
    end

    it 'returns false for Alias' do
      name = described_class.new(
        text: 'Test',
        name_type: Ammitto::Sources::Au::NameType::ALIAS,
        script: 'Latn'
      )
      expect(name.primary?).to be false
    end
  end

  describe '#original_script?' do
    it 'returns true for Original Script' do
      name = described_class.new(
        text: 'محمد',
        name_type: Ammitto::Sources::Au::NameType::ORIGINAL_SCRIPT,
        script: 'Arab'
      )
      expect(name.original_script?).to be true
    end
  end

  describe '#strong_alias?' do
    it 'returns true for strong alias' do
      name = described_class.new(
        text: 'Test',
        name_type: Ammitto::Sources::Au::NameType::ALIAS,
        script: 'Latn',
        alias_strength: Ammitto::Sources::Au::AliasStrength::STRONG
      )
      expect(name.strong_alias?).to be true
    end
  end
end

RSpec.describe Ammitto::Sources::Au::Sanction do
  describe '#effects' do
    it 'returns empty array when all flags are false' do
      sanction = described_class.new(
        targeted_financial_sanction: false,
        travel_ban: false,
        arms_embargo: false,
        maritime_restriction: false
      )
      expect(sanction.effects).to eq([])
    end

    it 'returns targeted_financial_sanction when TFS is true' do
      sanction = described_class.new(
        targeted_financial_sanction: true,
        travel_ban: false,
        arms_embargo: false,
        maritime_restriction: false
      )
      expect(sanction.effects).to eq(['targeted_financial_sanction'])
    end

    it 'returns multiple effects when multiple flags are true' do
      sanction = described_class.new(
        targeted_financial_sanction: true,
        travel_ban: true,
        arms_embargo: false,
        maritime_restriction: false
      )
      expect(sanction.effects).to contain_exactly('targeted_financial_sanction', 'travel_ban')
    end

    it 'returns maritime_restriction when set' do
      sanction = described_class.new(
        targeted_financial_sanction: false,
        travel_ban: false,
        arms_embargo: false,
        maritime_restriction: true
      )
      expect(sanction.effects).to eq(['maritime_restriction'])
    end
  end

  describe '#regime_type' do
    it 'returns :autonomous for autonomous sanctions' do
      sanction = described_class.new(committees: 'Autonomous (Iran)')
      expect(sanction.regime_type).to eq(:autonomous)
    end

    it 'returns :un_security_council for UNSC sanctions' do
      sanction = described_class.new(committees: '1737 (Iran)')
      expect(sanction.regime_type).to eq(:un_security_council)
    end

    it 'returns nil when committees is nil' do
      sanction = described_class.new(committees: nil)
      expect(sanction.regime_type).to be_nil
    end
  end
end

RSpec.describe Ammitto::Sources::Au::FlexibleDate do
  describe '.parse' do
    it 'parses full date "5 May 1957"' do
      date = described_class.parse('5 May 1957')
      expect(date.year).to eq(1957)
      expect(date.month).to eq(5)
      expect(date.day).to eq(5)
      expect(date.precision).to eq('full')
    end

    it 'parses month/year "May 1957"' do
      date = described_class.parse('May 1957')
      expect(date.year).to eq(1957)
      expect(date.month).to eq(5)
      expect(date.day).to be_nil
      expect(date.precision).to eq('month')
    end

    it 'parses year only "1957"' do
      date = described_class.parse('1957')
      expect(date.year).to eq(1957)
      expect(date.precision).to eq('year')
    end

    it 'parses circa date "circa 1957"' do
      date = described_class.parse('circa 1957')
      expect(date.year).to eq(1957)
      expect(date.circa).to be true
      expect(date.precision).to eq('circa')
    end

    it 'returns nil for empty string' do
      expect(described_class.parse('')).to be_nil
    end

    it 'returns nil for nil' do
      expect(described_class.parse(nil)).to be_nil
    end
  end

  describe '#to_date' do
    it 'converts to Date object' do
      date = described_class.parse('5 May 1957')
      expect(date.to_date).to eq(Date.new(1957, 5, 5))
    end
  end
end

RSpec.describe Ammitto::Sources::Au::Location do
  describe '.parse' do
    it 'parses "Yazd, Iran"' do
      loc = described_class.parse('Yazd, Iran')
      expect(loc.city).to eq('Yazd')
      expect(loc.country).to eq('Iran')
    end

    it 'parses single location "Iran"' do
      loc = described_class.parse('Iran')
      expect(loc.country).to eq('Iran')
    end
  end
end

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

RSpec.describe Ammitto::Transformers::AuTransformer do
  let(:transformer) { described_class.new }

  describe '#transform' do
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
