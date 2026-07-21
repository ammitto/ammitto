# frozen_string_literal: true

require 'spec_helper'
require 'nokogiri'

# Require the extractor
require_relative '../../../lib/ammitto/extractors/uk_extractor'

RSpec.describe Ammitto::Extractors::UkExtractor do
  let(:extractor) { described_class.new }

  describe '#code' do
    it 'returns :uk' do
      expect(extractor.code).to eq(:uk)
    end
  end

  describe '#authority_name' do
    it 'returns United Kingdom (OFSI)' do
      expect(extractor.authority_name).to eq('United Kingdom (OFSI)')
    end
  end

  describe '#api_endpoint' do
    it 'returns the UK sanctions list URL' do
      expect(extractor.api_endpoint).to eq(
        'https://sanctionslist.fcdo.gov.uk/docs/UK-Sanctions-List.xml'
      )
    end
  end

  describe '#authority' do
    it 'returns authority hash with correct values' do
      expect(extractor.authority).to eq({
                                          id: 'uk',
                                          name: 'United Kingdom (OFSI)',
                                          country_code: 'UK'
                                        })
    end
  end

  describe '#extract_entities' do
    let(:xml) do
      <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <Designations>
          <Designation>
            <UniqueID>TEST001</UniqueID>
            <OFSIGroupID>12345</OFSIGroupID>
            <UNReferenceNumber>TAe.010</UNReferenceNumber>
            <Names>
              <Name>
                <Name6>TEST ORGANIZATION</Name6>
                <NameType>Primary Name</NameType>
              </Name>
            </Names>
            <RegimeName>Test Sanctions Regime</RegimeName>
            <IndividualEntityShip>Entity</IndividualEntityShip>
            <Addresses>
              <Address>
                <AddressLine1>123 Test Street</AddressLine1>
                <AddressLine5>Test City</AddressLine5>
                <AddressLine6>Test Province</AddressLine6>
                <AddressCountry>Test Country</AddressCountry>
              </Address>
            </Addresses>
          </Designation>
          <Designation>
            <UniqueID>TEST002</UniqueID>
            <Names>
              <Name>
                <Name6>John Doe</Name6>
                <NameType>Primary Name</NameType>
              </Name>
            </Names>
            <IndividualEntityShip>Individual</IndividualEntityShip>
            <IndividualDetails>
              <Individual>
                <DOBs>
                  <DOB>15/03/1970</DOB>
                </DOBs>
                <Nationalities>
                  <Nationality>British</Nationality>
                </Nationalities>
                <BirthDetails>
                  <Location>
                    <TownOfBirth>London</TownOfBirth>
                    <CountryOfBirth>United Kingdom</CountryOfBirth>
                  </Location>
                </BirthDetails>
              </Individual>
            </IndividualDetails>
          </Designation>
        </Designations>
      XML
    end

    let(:doc) { Nokogiri::XML(xml) }
    let(:entities) { extractor.extract_entities(doc) }

    it 'extracts all entities' do
      expect(entities.length).to eq(2)
    end

    it 'extracts organization entity correctly' do
      org = entities.first

      expect(org['@id']).to eq('https://www.ammitto.org/entity/uk/TEST001')
      expect(org['@type']).to eq('OrganizationEntity')
      expect(org['entityType']).to eq('organization')
      expect(org['names'].first['fullName']).to eq('TEST ORGANIZATION')
    end

    it 'extracts person entity correctly' do
      person = entities.last

      expect(person['@id']).to eq('https://www.ammitto.org/entity/uk/TEST002')
      expect(person['@type']).to eq('PersonEntity')
      expect(person['entityType']).to eq('person')
      expect(person['nationalities']).to include('British')
    end

    it 'extracts birth info correctly' do
      person = entities.last

      expect(person['birthInfo']).to be_an(Array)
      expect(person['birthInfo'].first['date']).to eq('15/03/1970')
    end

    it 'extracts addresses correctly' do
      org = entities.first

      expect(org['addresses']).to be_an(Array)
      expect(org['addresses'].first['city']).to eq('Test City')
    end
  end

  describe '#extract_entries' do
    let(:xml) do
      <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <Designations>
          <Designation>
            <UniqueID>TEST001</UniqueID>
            <DateDesignated>01/01/2020</DateDesignated>
            <RegimeName>The Test (Sanctions) Regulations 2020</RegimeName>
            <IndividualEntityShip>Entity</IndividualEntityShip>
            <SanctionsImposedIndicators>
              <AssetFreeze>true</AssetFreeze>
              <ArmsEmbargo>false</ArmsEmbargo>
              <TravelBan>true</TravelBan>
            </SanctionsImposedIndicators>
            <UKStatementofReasons>Test reason</UKStatementofReasons>
          </Designation>
        </Designations>
      XML
    end

    let(:doc) { Nokogiri::XML(xml) }
    let(:entries) { extractor.extract_entries(doc) }

    it 'extracts all entries' do
      expect(entries.length).to eq(1)
    end

    it 'extracts entry correctly' do
      entry = entries.first

      expect(entry['@id']).to eq('https://www.ammitto.org/entry/uk/TEST001')
      expect(entry['@type']).to eq('SanctionEntry')
      expect(entry['referenceNumber']).to eq('TEST001')
      expect(entry['status']).to eq('active')
    end

    it 'extracts regime correctly' do
      entry = entries.first

      expect(entry['regime']).to be_a(Hash)
      expect(entry['regime']['name']).to eq('The Test (Sanctions) Regulations 2020')
    end

    it 'extracts effects from indicators' do
      entry = entries.first

      expect(entry['effects']).to be_an(Array)
      effect_types = entry['effects'].map { |e| e['effectType'] }
      expect(effect_types).to include('asset_freeze')
      expect(effect_types).to include('travel_ban')
      expect(effect_types).not_to include('arms_embargo')
    end

    it 'extracts period correctly' do
      entry = entries.first

      expect(entry['period']).to be_a(Hash)
      expect(entry['period']['listedDate']).to eq('2020-01-01')
    end

    it 'extracts reasons correctly' do
      entry = entries.first

      expect(entry['reasons']).to be_an(Array)
      expect(entry['reasons'].first['description']).to eq('Test reason')
    end
  end

  describe 'Registry integration' do
    it 'is registered in the registry' do
      expect(Ammitto::Extractors::Registry.get(:uk)).to eq(described_class)
    end
  end
end
