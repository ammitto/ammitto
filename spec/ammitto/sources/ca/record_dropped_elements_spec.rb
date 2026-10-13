# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Ca::Record do
  # Records transcribed from sema-lmes.xml fetched 2026-10-13: Belarus
  # item 56 (alias), Russia 1.1 item 1 (a vessel), Syria Part 2 item 60
  # (title) and Iran Part 2 item 116, whose ShipIMONumber element holds
  # a Persian personal name.
  let(:dropped_xml) do
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
          <LastName-NomDeFamille>Davoud Moazami</LastName-NomDeFamille>
          <GivenName-Prenom>Goudrazi</GivenName-Prenom>
          <ShipIMONumber-NumeroOMIDuNavire>مجتبی خامنه‌ای</ShipIMONumber-NumeroOMIDuNavire>
          <Schedule-Annexe>1, Part 2</Schedule-Annexe>
          <Item-NumeroDarticle>116</Item-NumeroDarticle>
          <DateOfListing-DateDinscription>2026-09-22</DateOfListing-DateDinscription>
        </record>
      </data-set>
    XML
  end
  let(:aliased) { dropped[0] }
  let(:ship) { dropped[1] }
  let(:titled) { dropped[2] }
  let(:persian_imo) { dropped[3] }

  def dropped
    @dropped ||= Ammitto::Sources::Ca::SanctionsList.from_xml(dropped_xml).records
  end

  it 'reads the alias' do
    expect(aliased.alias_names).to eq(['Aliaksei Aleksin'])
  end

  it 'splits aliases on semicolons only' do
    record = described_class.new(
      aliases: 'Mosgorsud; Московский городской суд or Мосгорсуд; '
    )

    expect(record.alias_names).to eq(
      ['Mosgorsud', 'Московский городской суд or Мосгорсуд']
    )
  end

  it 'reads the IMO number and ship type of a vessel' do
    expect(ship.imo_number).to eq('7612448')
    expect(ship).to be_vessel
    expect(ship.english_title_or_ship_type).to eq('General Cargo/Multi Purpose')
  end

  it 'reads a title in its English half' do
    expect(titled.english_title_or_ship_type).to eq('Major General')
    expect(titled.title_or_ship_type).to include('major-général')
  end

  it 'does not take a personal name in the IMO element for an IMO number' do
    expect(persian_imo.ship_imo_number).not_to be_nil
    expect(persian_imo.imo_number).to be_nil
    expect(persian_imo).not_to be_vessel
  end

  it 'carries all three through processed YAML' do
    round_tripped = described_class.from_yaml(ship.to_yaml)

    expect(round_tripped.imo_number).to eq('7612448')
    expect(described_class.from_yaml(aliased.to_yaml).alias_names)
      .to eq(['Aliaksei Aleksin'])
    expect(described_class.from_yaml(titled.to_yaml).title_or_ship_type)
      .to eq(titled.title_or_ship_type)
  end
end
