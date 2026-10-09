# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'thor'
require 'ammitto/sources/au'
require 'ammitto/cli'
require 'ammitto/cli/fetch_command'

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

  # DFAT separates citizenships with a semicolon and leaves commas inside
  # country names. "Congo, Democratic Republic of the;Rwanda" is both at once:
  # splitting on the comma invented two countries that do not exist and lost
  # Rwanda entirely. Measured on the live workbook, 389 of 6304 non-empty
  # cells carry a semicolon and 79 carry a comma.
  describe 'citizenship separator' do
    let(:multi_citizenship_csv) do
      header, individual = sample_csv.lines.first(2)
      fields = individual.chomp.split(',', -1)
      # Citizenship is the eighth column; quote it so the comma inside the
      # country name survives CSV parsing the way DFAT's export does.
      fields[7] = '"Congo, Democratic Republic of the;Rwanda"'
      "#{header}#{fields.join(',')}\n"
    end

    it 'splits on the semicolon and keeps a comma inside a country name' do
      list = described_class.from_csv(multi_citizenship_csv)

      expect(list.individuals.first.citizenships)
        .to eq(['Congo, Democratic Republic of the', 'Rwanda'])
    end
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

    it 'keeps an unknown type and its continuation row as one generic entity' do
      allow(Ammitto::Logger).to receive(:warn)

      csv = <<~CSV
        Reference,Name of Individual or Entity,Type,Name Type,Alias Strength,Address,Additional Information,Listing Information,Committees,Control Date,Instrument of Designation,Targeted Financial Sanction,Travel Ban,Arms Embargo,Maritime Restriction
        9000,SHIP OWNER,Ship Owner,Primary Name,,Port Louis,Role,Listed,Autonomous (Vessels),6/18/25,Instrument,TRUE,FALSE,FALSE,TRUE
        9000a,SHIP OWNER ALIAS,Ship Owner,Alias,Strong,Port Louis,Role,Listed,Autonomous (Vessels),6/18/25,Instrument,TRUE,FALSE,FALSE,TRUE
        9001,UNKNOWN PARTY,Aircraft,Primary Name,,Sydney,Role,Listed,Australia,1/1/25,Instrument,FALSE,FALSE,FALSE,FALSE
      CSV

      parsed = described_class.from_csv(csv)
      generic = parsed.generic_entities

      expect(generic.size).to eq(2)
      expect(generic.first).to be_a(Ammitto::Sources::Au::GenericEntity)
      expect(generic.first.reference).to eq('9000')
      expect(generic.first.entity_type).to eq('Ship Owner')
      expect(generic.first.names.map(&:text)).to contain_exactly('SHIP OWNER', 'SHIP OWNER ALIAS')
      expect(parsed.items).to include(*generic)
      expect(parsed.count).to eq(2)
      expect(Ammitto::Logger).to have_received(:warn).with(
        'au: unknown Type "Ship Owner" on 2 rows; kept as generic entities'
      )
      expect(Ammitto::Logger).to have_received(:warn).with(
        'au: unknown Type "Aircraft" on 1 row; kept as generic entities'
      )
      expect(Ammitto::Logger).to have_received(:warn).twice
    end

    it 'leaves two unknown Types under one reference for the fetch collision guard to refuse' do
      allow(Ammitto::Logger).to receive(:warn)

      csv = <<~CSV
        Reference,Name of Individual or Entity,Type,Name Type,Alias Strength,Address,Additional Information,Listing Information,Committees,Control Date,Instrument of Designation,Targeted Financial Sanction,Travel Ban,Arms Embargo,Maritime Restriction
        9000,SHIP OWNER,Ship Owner,Primary Name,,Port Louis,Role,Listed,Autonomous (Vessels),6/18/25,Instrument,TRUE,FALSE,FALSE,TRUE
        9000a,SOME PLANE,Aircraft,Primary Name,,Sydney,Role,Listed,Australia,1/1/25,Instrument,FALSE,FALSE,FALSE,FALSE
      CSV

      parsed = described_class.from_csv(csv)
      expect(parsed.generic_entities.map(&:entity_type)).to eq(['Ship Owner', 'Aircraft'])

      command = Ammitto::Cmd::FetchCommand.new(Thor::CoreExt::HashWithIndifferentAccess.new, ['au'])
      Dir.mktmpdir do |dir|
        expect { command.send(:write_items, :au, parsed.items, dir) }
          .to raise_error(Ammitto::Cmd::Fetch::FilenameCollisionError)
      end
    end

    it 'treats a blank Type as a generic entity and warns with its spelling' do
      allow(Ammitto::Logger).to receive(:warn)

      row = Array.new(19)
      row[0] = '9002'
      row[1] = 'BLANK TYPE'
      row[2] = ''
      row[3] = 'Primary Name'
      csv = sample_csv.lines.first + CSV.generate_line(row)

      parsed = described_class.from_csv(csv)

      expect(parsed.generic_entities.first.entity_type).to eq('')
      expect(YAML.safe_load(parsed.generic_entities.first.to_yaml)).to include('entity_type' => '')
      expect(Ammitto::Logger).to have_received(:warn).with(
        'au: unknown Type "" on 1 row; kept as generic entities'
      )
    end

    it 'warns for a nil Type while preserving nil' do
      allow(Ammitto::Logger).to receive(:warn)

      csv = "#{sample_csv.lines.first}9003,MISSING TYPE\n"
      parsed = described_class.from_csv(csv)

      expect(parsed.generic_entities.first.entity_type).to be_nil
      expect(YAML.safe_load(parsed.generic_entities.first.to_yaml)).to include('entity_type' => nil)
      expect(Ammitto::Logger).to have_received(:warn).with(
        'au: unknown Type nil on 1 row; kept as generic entities'
      )
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
