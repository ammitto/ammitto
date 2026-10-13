# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Ca::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :ca' do
      expect(transformer.source_code).to eq(:ca)
    end
  end

  describe '#authority' do
    it 'returns CA authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('ca')
      expect(auth.name).to eq('Canada (SEFO)')
    end
  end

  describe '#transform' do
    # Records from sema-lmes.xml fetched 2026-10-13.
    let(:xml) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <data-set>
          <record>
            <Country-Pays>Belarus / Bélarus</Country-Pays>
            <LastName-NomDeFamille>Oleksin</LastName-NomDeFamille>
            <GivenName-Prenom>Aleksey</GivenName-Prenom>
            <Aliases-Alias>Aliaksei Aleksin</Aliases-Alias>
            <Schedule-Annexe>1, Part 1</Schedule-Annexe>
            <Item-NumeroDarticle>56</Item-NumeroDarticle>
            <DateOfListing-DateDinscription>2021-06-17</DateOfListing-DateDinscription>
          </record>
          <record>
            <Country-Pays>Russia / Russie</Country-Pays>
            <EntityOrShip-EntiteOuNavire>Balitiyskiy III</EntityOrShip-EntiteOuNavire>
            <TitleOrShipType-TitreOuTypeDeNavire>General Cargo/Multi Purpose | Cargo classique/navire polyvalent</TitleOrShipType-TitreOuTypeDeNavire>
            <ShipIMONumber-NumeroOMIDuNavire>7612448</ShipIMONumber-NumeroOMIDuNavire>
            <DateOfBirthOrShipBuildDate-DateDeNaissanceOuDateDeConstructionDuNavire>1980</DateOfBirthOrShipBuildDate-DateDeNaissanceOuDateDeConstructionDuNavire>
            <Schedule-Annexe>1.1</Schedule-Annexe>
            <Item-NumeroDarticle>1</Item-NumeroDarticle>
            <DateOfListing-DateDinscription>2025-02-21</DateOfListing-DateDinscription>
          </record>
          <record>
            <Country-Pays>Syria / Syrie</Country-Pays>
            <TitleOrShipType-TitreOuTypeDeNavire>Major General | major-général</TitleOrShipType-TitreOuTypeDeNavire>
            <LastName-NomDeFamille>Al-Ahmad</LastName-NomDeFamille>
            <GivenName-Prenom>Jumah </GivenName-Prenom>
            <Schedule-Annexe>Part 2</Schedule-Annexe>
            <Item-NumeroDarticle>60</Item-NumeroDarticle>
            <DateOfListing-DateDinscription>2011-12-23</DateOfListing-DateDinscription>
          </record>
          <record>
            <Country-Pays>Iran</Country-Pays>
            <LastName-NomDeFamille>Eskandar</LastName-NomDeFamille>
            <GivenName-Prenom>Momeni</GivenName-Prenom>
            <ShipIMONumber-NumeroOMIDuNavire>داوود معظمی گودرزی</ShipIMONumber-NumeroOMIDuNavire>
            <DateOfBirthOrShipBuildDate-DateDeNaissanceOuDateDeConstructionDuNavire>1962-01-15</DateOfBirthOrShipBuildDate-DateDeNaissanceOuDateDeConstructionDuNavire>
            <Schedule-Annexe>1, Part 2</Schedule-Annexe>
            <Item-NumeroDarticle>117</Item-NumeroDarticle>
            <DateOfListing-DateDinscription>2026-09-22</DateOfListing-DateDinscription>
          </record>
        </data-set>
      XML
    end

    let(:results) do
      records = Ammitto::Sources::Ca::SanctionsList.from_xml(xml).records
      records.map { |record| transformer.transform(record)[:entity] }
    end

    it 'publishes the alias as a non-primary name' do
      names = results[0].names

      expect(names.map(&:full_name)).to eq(['Aleksey Oleksin', 'Aliaksei Aleksin'])
      expect(names.map(&:is_primary)).to eq([true, false])
    end

    it 'publishes a vessel with its IMO number, type and build year' do
      vessel = results[1]

      expect(vessel).to be_a(Ammitto::VesselEntity)
      expect(vessel.imo_number).to eq('7612448')
      expect(vessel.vessel_type).to eq('General Cargo/Multi Purpose')
      expect(vessel.build_year).to eq(1980)
    end

    it 'publishes a title' do
      expect(results[2].title).to eq('Major General')
    end

    it 'publishes a date of birth' do
      expect(results[3].birth_info.first.date).to eq(Date.new(1962, 1, 15))
    end

    it 'keeps a record whose IMO element holds a name a person' do
      expect(results[3]).to be_a(Ammitto::PersonEntity)
    end

    describe 'dates of birth the source states loosely' do
      let(:birth_for) do
        lambda do |value|
          record = Ammitto::Sources::Ca::Record.new(
            country: 'Iran', schedule: '1', item: '1', last_name: 'Karnienko',
            date_of_birth_or_ship_build_date: value
          )
          transformer.transform(record)[:entity].birth_info
        end
      end

      ['circa 1980', 'circa1980', 'c. 1980', 'c1980', 'Approximately: 1980'].each do |value|
        it "preserves the approximation marker in #{value.inspect}" do
          birth = birth_for.call(value).first

          expect(birth.year).to eq(1980)
          expect(birth.date).to be_nil
          expect(birth.circa).to be(true)
        end
      end

      it 'preserves an approximate complete date without changing its precision' do
        birth = birth_for.call('circa 1959-12-28').first

        expect(birth.date).to eq(Date.new(1959, 12, 28))
        expect(birth.circa).to be(true)
      end

      it 'keeps an exact year exact' do
        expect(birth_for.call('1980').first.circa).to be(false)
      end

      it 'keeps a year range as a range' do
        birth = birth_for.call('1980 to 1982').first

        expect([birth.year_range_from, birth.year_range_to]).to eq([1980, 1982])
        expect(birth.date).to be_nil
      end

      it 'keeps the stated year and approximation of a year and month' do
        birth = birth_for.call('circa 1983-09').first

        expect(birth.year).to eq(1983)
        expect(birth.date).to be_nil
        expect(birth.circa).to be(true)
      end

      it 'keeps the year of a year and month' do
        expect(birth_for.call('1983-09').map(&:year)).to eq([1983])
      end

      it 'publishes no birth date for alternatives' do
        expect(birth_for.call('1972-08-10 or 1972-08-11')).to be_empty
        expect(birth_for.call('1965-07-15 OR 1969-09-28')).to be_empty
      end

      it 'publishes no empty birth info for an unreadable value' do
        expect(birth_for.call('born in the early 1970s')).to be_empty
        expect(birth_for.call('Sep-99')).to be_empty
      end

      it 'trims a date written with a leading space' do
        expect(birth_for.call(' 1959-12-28').first.date).to eq(Date.new(1959, 12, 28))
      end
    end

    it 'normalizes line breaks and non-breaking spaces in a vessel type and aliases' do
      record = Ammitto::Sources::Ca::Record.new(
        country: 'Iran', schedule: '1', item: '2', entity_or_ship: 'Example',
        ship_imo_number: '7612448',
        title_or_ship_type: "Chemical/\nProducts Tanker | Navire-citerne",
        aliases: "First Alias\u00a0; Second\nAlias"
      )
      vessel = transformer.transform(record)[:entity]

      expect(vessel.vessel_type).to eq('Chemical/ Products Tanker')
      expect(vessel.names.map(&:full_name)).to eq(['Example', 'First Alias', 'Second Alias'])
    end
  end
end
