# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Eu::SanctionEntity do
  # Entities shortened from the EU full sanctions list generated
  # 2026-10-12 (xmlFullSanctionsList_1_1). The attributes under test
  # (designationDate, validTo, issueDate, issuedBy, poBox, place and
  # contactInfo) are copied unchanged; the regulation and nameAlias
  # elements around them are abbreviated, and the Iltifat village address
  # in EU.620.38 belongs to EU.471.56 in the list.
  # EU.3097.55 has a designationDate and a passport with validTo.
  # EU.3510.20 has a passport with issueDate and issuedBy. EU.522.39 has
  # addresses with contactInfo and EU.620.38 one with a poBox. EU.35.2 is
  # one of the entities that state no designationDate at all.
  let(:xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <export xmlns="http://eu.europa.ec/fpi/fsd/export">
        <sanctionEntity designationDate="2002-01-11" designationDetails="" unitedNationId="" euReferenceNumber="EU.3097.55" logicalId="537">
          <regulation regulationType="amendment" organisationType="commission" publicationDate="2015-08-14" entryIntoForceDate="2015-08-14" numberTitle="2015/1390 (OJ L215)" programme="TAQA" logicalId="83220"/>
          <subjectType code="person" classificationCode="P"/>
          <nameAlias firstName="" middleName="" lastName="" wholeName="Abdul Rahman" function="" title="" nameLanguage="" strong="true" regulationLanguage="en" logicalId="4913"/>
          <identification diplomatic="false" knownExpired="true" knownFalse="false" reportedLost="false" revokedByIssuer="false" issuedBy="" latinNumber="" nameOnDocument="" number="347834" validTo="2014-02-21" region="" identificationTypeCode="passport" identificationTypeDescription="National passport" countryIso2Code="LY" countryDescription="LIBYA" regulationLanguage="en" logicalId="106108"/>
          <identification diplomatic="false" knownExpired="false" knownFalse="false" reportedLost="false" revokedByIssuer="false" issuedBy="" latinNumber="" nameOnDocument="" number="203037" region="TRIPOLI" identificationTypeCode="passport" identificationTypeDescription="National passport" countryIso2Code="LY" countryDescription="LIBYA" regulationLanguage="en" logicalId="206"/>
        </sanctionEntity>
        <sanctionEntity designationDate="2003-11-03" designationDetails="" unitedNationId="" euReferenceNumber="EU.3510.20" logicalId="1079">
          <regulation regulationType="amendment" organisationType="council" publicationDate="2025-01-31" entryIntoForceDate="2025-02-01" numberTitle="2025/206 (L 202500206)" programme="TERR" logicalId="207667"/>
          <subjectType code="person" classificationCode="P"/>
          <nameAlias firstName="" middleName="" lastName="" wholeName="Dawood Ibrahim Kaskar" function="" title="" nameLanguage="EN" strong="true" regulationLanguage="en" logicalId="1"/>
          <identification diplomatic="false" knownExpired="false" knownFalse="false" reportedLost="false" revokedByIssuer="true" issueDate="1985-06-04" issuedBy="Bombay" latinNumber="" nameOnDocument="" number="A-333602" region="" identificationTypeCode="passport" identificationTypeDescription="National passport" countryIso2Code="IN" countryDescription="INDIA" regulationLanguage="en" logicalId="51"/>
        </sanctionEntity>
        <sanctionEntity designationDate="2001-10-06" designationDetails="" unitedNationId="" euReferenceNumber="EU.522.39" logicalId="330">
          <regulation regulationType="amendment" organisationType="commission" publicationDate="2024-01-15" entryIntoForceDate="2024-01-16" numberTitle="2024/328 (OJ L15012024)" programme="TAQA" logicalId="188894"/>
          <subjectType code="enterprise" classificationCode="E"/>
          <nameAlias firstName="" middleName="" lastName="" wholeName="Al Rashid Trust" function="" title="" nameLanguage="EN" strong="true" regulationLanguage="en" logicalId="908"/>
          <address city="Karachi" street="302b-40 Good Earth Court, Opposite Pia Planitarium, Block 13a, Gushan-I Igbal" poBox="" zipCode="" region="" place="" asAtListingTime="false" countryIso2Code="PK" countryDescription="PAKISTAN" regulationLanguage="en" logicalId="368">
            <contactInfo key="PHONE" value="497 92 63"/>
          </address>
          <address city="Karachi" street="Kitab Ghar, Darul Ifta Wal Irshad, Nazimbad No 4" poBox="" zipCode="" region="" place="" asAtListingTime="false" countryIso2Code="PK" countryDescription="PAKISTAN" regulationLanguage="en" logicalId="367">
            <contactInfo key="PHONE" value="668 33 01; 0300- 820 91 99"/>
            <contactInfo key="FAX" value="662 38 14"/>
          </address>
        </sanctionEntity>
        <sanctionEntity designationDate="2002-11-21" designationDetails="" unitedNationId="" euReferenceNumber="EU.620.38" logicalId="983">
          <regulation regulationType="amendment" organisationType="commission" publicationDate="2024-01-17" entryIntoForceDate="2024-01-18" numberTitle="2024/372 (OJ L18012024)" programme="TAQA" logicalId="188895"/>
          <subjectType code="enterprise" classificationCode="E"/>
          <address city="Khartoum" street="" poBox="P.O. Box 1937" zipCode="" region="" place="" asAtListingTime="false" countryIso2Code="SD" countryDescription="SUDAN" regulationLanguage="en" logicalId="161574"/>
          <address city="Iltifat village, Shakardara District," street="" poBox="" zipCode="" region="Kabul Province" place="Iltifat village" asAtListingTime="false" countryIso2Code="AF" countryDescription="AFGHANISTAN" regulationLanguage="en" logicalId="111266"/>
        </sanctionEntity>
        <sanctionEntity designationDetails="" unitedNationId="" euReferenceNumber="EU.35.2" logicalId="39">
          <regulation regulationType="regulation" organisationType="commission" publicationDate="2003-07-08" entryIntoForceDate="2003-07-07" numberTitle="1210/2003 (OJ L169)" programme="IRQ" logicalId="348"/>
          <subjectType code="person" classificationCode="P"/>
          <nameAlias firstName="" middleName="" lastName="" wholeName="Hani Abdel-Latif Tilfah Al-Tikriti" function="" title="" nameLanguage="FR" strong="true" regulationLanguage="en" logicalId="388"/>
        </sanctionEntity>
      </export>
    XML
  end

  let(:entities) { Ammitto::Sources::Eu::Export.from_xml(xml).sanction_entities }
  let(:transformer) { Ammitto::Sources::Eu::Transformer.new }

  def transform(index)
    transformer.transform(entities[index])
  end

  it 'reads designationDate' do
    expect(entities[1].designation_date).to eq('2003-11-03')
    expect(entities[0].designation_date).to eq('2002-01-11')
    expect(entities[4].designation_date).to be_nil
  end

  it 'reads document validTo, issueDate and issuedBy' do
    expect(entities[0].identifications.map(&:valid_to)).to eq(['2014-02-21', nil])
    passport = entities[1].identifications.first
    expect([passport.issue_date, passport.issued_by]).to eq(%w[1985-06-04 Bombay])
  end

  it 'reads contactInfo, place and poBox on addresses' do
    contacts = entities[2].addresses.last.contact_infos
    expect(contacts.map { |c| [c.key, c.value] }).to eq(
      [['PHONE', '668 33 01; 0300- 820 91 99'], ['FAX', '662 38 14']]
    )
    expect(entities[3].addresses.map(&:po_box)).to eq(['P.O. Box 1937', ''])
    expect(entities[3].addresses.map(&:place)).to eq(['', 'Iltifat village'])
  end

  it 'keeps the new fields through processed YAML' do
    round_tripped = described_class.from_yaml(entities[1].to_yaml)
    expect(round_tripped.designation_date).to eq('2003-11-03')
    expect(round_tripped.identifications.first.issued_by).to eq('Bombay')

    with_contacts = described_class.from_yaml(entities[2].to_yaml)
    expect(with_contacts.addresses.last.contact_infos.map(&:key)).to eq(%w[PHONE FAX])
  end

  it 'lists the entity on its designation date' do
    expect(transform(0)[:entry].period.listed_date).to eq(Date.new(2002, 1, 11))
    expect(transform(1)[:entry].period.listed_date).to eq(Date.new(2003, 11, 3))
  end

  it 'falls back to the regulation date when no designation date is stated' do
    expect(transform(4)[:entry].period.listed_date).to eq(Date.new(2003, 7, 8))
  end

  it 'publishes the document expiry and issue dates' do
    expired, other = transform(0)[:entity].identifications
    expect(expired.expiry_date).to eq(Date.new(2014, 2, 21))
    expect(other.expiry_date).to be_nil

    expect(transform(1)[:entity].identifications.first.issue_date).to eq(Date.new(1985, 6, 4))
  end

  it 'passes the address PO box to the harmonized address' do
    expect(transform(3)[:entity].addresses.map(&:po_box)).to eq(['P.O. Box 1937', nil])
  end
end
