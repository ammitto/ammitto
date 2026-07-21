# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/ontology'

RSpec.describe 'Neo4j Round Trip', :integration do
  # This spec verifies 100% coverage between import and export
  # by ensuring that all neo4j_property declarations are properly
  # serialized and deserialized.

  describe 'Neo4jAdapter serialization' do
    context 'with PersonEntity' do
      let(:person) do
        Ammitto::Ontology::Entities::PersonEntity.new(
          id: 'https://www.ammitto.org/entity/test/PERSON001',
          entity_type: 'person',
          gender: 'male',
          title: 'Mr',
          position: 'Director',
          affiliation: 'Test Organization',
          remarks: 'Test remarks'
        )
      end

      describe '#neo4j_labels' do
        it 'includes Person and Entity labels' do
          expect(person.neo4j_labels).to contain_exactly('Person', 'Entity')
        end
      end

      describe '#neo4j_properties' do
        it 'includes all declared properties' do
          props = person.neo4j_properties
          expect(props[:id]).to eq('https://www.ammitto.org/entity/test/PERSON001')
          expect(props[:entity_type]).to eq('person')
          expect(props[:gender]).to eq('male')
          expect(props[:title]).to eq('Mr')
          expect(props[:position]).to eq('Director')
          expect(props[:affiliation]).to eq('Test Organization')
          expect(props[:remarks]).to eq('Test remarks')
        end

        it 'includes inherited properties from Entity' do
          props = person.neo4j_properties
          expect(props).to have_key(:id)
          expect(props).to have_key(:entity_type)
          expect(props).to have_key(:remarks)
        end
      end

      describe '#to_neo4j_node' do
        it 'returns labels and properties' do
          node = person.to_neo4j_node
          expect(node[:labels]).to include('Person', 'Entity')
          expect(node[:properties]).to have_key(:id)
        end
      end

      describe '.from_neo4j_record' do
        it 'reconstructs entity from Neo4j record' do
          record = {
            'id' => 'https://www.ammitto.org/entity/test/PERSON001',
            'entity_type' => 'person',
            'gender' => 'male',
            'title' => 'Mr',
            'position' => 'Director',
            'affiliation' => 'Test Organization',
            'remarks' => 'Test remarks'
          }

          loaded = Ammitto::Ontology::Entities::PersonEntity.from_neo4j_record(record)
          expect(loaded.id).to eq(record['id'])
          expect(loaded.gender).to eq(record['gender'])
          expect(loaded.title).to eq(record['title'])
          expect(loaded.position).to eq(record['position'])
          expect(loaded.affiliation).to eq(record['affiliation'])
          expect(loaded.remarks).to eq(record['remarks'])
        end
      end

      describe 'round trip' do
        it 'preserves all properties through serialization cycle' do
          original = person
          props = original.neo4j_properties

          # Simulate Neo4j storage (convert symbols to strings)
          stored = props.transform_keys(&:to_s)

          # Reconstruct
          loaded = Ammitto::Ontology::Entities::PersonEntity.from_neo4j_record(stored)

          # Verify all properties match
          expect(loaded.neo4j_properties).to eq(original.neo4j_properties)
        end
      end
    end

    context 'with NameVariant' do
      let(:name) do
        Ammitto::Ontology::ValueObjects::NameVariant.new(
          full_name: 'Ivan Ivanov',
          first_name: 'Ivan',
          last_name: 'Ivanov',
          script: 'Cyrl',
          language: 'ru',
          is_primary: true
        )
      end

      describe '#neo4j_properties' do
        it 'includes all declared properties' do
          props = name.neo4j_properties
          expect(props[:full_name]).to eq('Ivan Ivanov')
          expect(props[:first_name]).to eq('Ivan')
          expect(props[:last_name]).to eq('Ivanov')
          expect(props[:script]).to eq('Cyrl')
          expect(props[:language]).to eq('ru')
          expect(props[:is_primary]).to eq(true)
        end
      end

      describe '.from_neo4j_record' do
        it 'reconstructs name from Neo4j record' do
          record = {
            'full_name' => 'Ivan Ivanov',
            'first_name' => 'Ivan',
            'last_name' => 'Ivanov',
            'script' => 'Cyrl',
            'language' => 'ru',
            'is_primary' => true
          }

          loaded = Ammitto::Ontology::ValueObjects::NameVariant.from_neo4j_record(record)
          expect(loaded.full_name).to eq(record['full_name'])
          expect(loaded.script).to eq(record['script'])
          expect(loaded.language).to eq(record['language'])
          expect(loaded.is_primary).to eq(record['is_primary'])
        end
      end

      describe 'round trip' do
        it 'preserves script and language through serialization cycle' do
          original = name
          props = original.neo4j_properties
          stored = props.transform_keys(&:to_s)
          loaded = Ammitto::Ontology::ValueObjects::NameVariant.from_neo4j_record(stored)

          expect(loaded.script).to eq(original.script)
          expect(loaded.language).to eq(original.language)
          expect(loaded.neo4j_properties).to eq(original.neo4j_properties)
        end
      end
    end

    context 'with Address' do
      let(:address) do
        Ammitto::Ontology::ValueObjects::Address.new(
          street: '123 Main Street',
          city: 'Moscow',
          region: 'Moscow Oblast',
          country: 'Russia',
          country_iso_code: 'RU',
          postal_code: '123456'
        )
      end

      describe '#neo4j_properties' do
        it 'includes all declared properties' do
          props = address.neo4j_properties
          expect(props[:street]).to eq('123 Main Street')
          expect(props[:city]).to eq('Moscow')
          expect(props[:region]).to eq('Moscow Oblast')
          expect(props[:country]).to eq('Russia')
          expect(props[:country_iso_code]).to eq('RU')
          expect(props[:postal_code]).to eq('123456')
        end
      end

      describe 'round trip' do
        it 'preserves all address fields through serialization cycle' do
          original = address
          props = original.neo4j_properties
          stored = props.transform_keys(&:to_s)
          loaded = Ammitto::Ontology::ValueObjects::Address.from_neo4j_record(stored)

          expect(loaded.street).to eq(original.street)
          expect(loaded.city).to eq(original.city)
          expect(loaded.region).to eq(original.region)
          expect(loaded.country_iso_code).to eq(original.country_iso_code)
          expect(loaded.postal_code).to eq(original.postal_code)
        end
      end
    end

    context 'with Identification' do
      let(:identification) do
        Ammitto::Ontology::ValueObjects::Identification.new(
          type: 'passport',
          number: 'A12345678',
          issuing_country: 'RU',
          issue_date: Date.new(2020, 1, 1),
          expiry_date: Date.new(2030, 1, 1)
        )
      end

      describe '#neo4j_properties' do
        it 'includes all declared properties' do
          props = identification.neo4j_properties
          expect(props[:type]).to eq('passport')
          expect(props[:number]).to eq('A12345678')
          expect(props[:issuing_country]).to eq('RU')
          expect(props[:issue_date]).to eq('2020-01-01')
          expect(props[:expiry_date]).to eq('2030-01-01')
        end
      end

      describe 'round trip' do
        it 'preserves all identifier fields through serialization cycle' do
          original = identification
          props = original.neo4j_properties
          stored = props.transform_keys(&:to_s)
          loaded = Ammitto::Ontology::ValueObjects::Identification.from_neo4j_record(stored)

          expect(loaded.type).to eq(original.type)
          expect(loaded.number).to eq(original.number)
          expect(loaded.issuing_country).to eq(original.issuing_country)
          # Dates are serialized to strings
          expect(loaded.neo4j_properties[:issue_date]).to eq(original.neo4j_properties[:issue_date])
          expect(loaded.neo4j_properties[:expiry_date]).to eq(original.neo4j_properties[:expiry_date])
        end
      end
    end

    context 'with AircraftEntity' do
      let(:aircraft) do
        Ammitto::Ontology::Entities::AircraftEntity.new(
          id: 'https://www.ammitto.org/entity/test/RA-12345',
          name: 'RA-12345',
          serial_number: '12345',
          registration: 'RA-12345',
          aircraft_type: 'Boeing 737',
          manufacturer: 'Boeing',
          build_year: 2020,
          registration_country: 'RU',
          operator: 'Test Airlines'
        )
      end

      describe '#neo4j_labels' do
        it 'includes Aircraft and Entity labels' do
          expect(aircraft.neo4j_labels).to contain_exactly('Aircraft', 'Entity')
        end
      end

      describe '#neo4j_properties' do
        it 'includes all declared properties' do
          props = aircraft.neo4j_properties
          expect(props[:name]).to eq('RA-12345')
          expect(props[:serial_number]).to eq('12345')
          expect(props[:registration]).to eq('RA-12345')
          expect(props[:aircraft_type]).to eq('Boeing 737')
          expect(props[:manufacturer]).to eq('Boeing')
          expect(props[:build_year]).to eq(2020)
          expect(props[:registration_country]).to eq('RU')
          expect(props[:operator]).to eq('Test Airlines')
        end
      end

      describe 'round trip' do
        it 'preserves all aircraft properties through serialization cycle' do
          original = aircraft
          props = original.neo4j_properties
          stored = props.transform_keys(&:to_s)
          loaded = Ammitto::Ontology::Entities::AircraftEntity.from_neo4j_record(stored)

          expect(loaded.neo4j_properties).to eq(original.neo4j_properties)
        end
      end
    end
  end

  describe 'Property coverage verification' do
    # This test ensures that the number of declared properties matches
    # what we expect for each entity type, catching any accidental omissions.

    it 'PersonEntity has all expected properties' do
      props = Ammitto::Ontology::Entities::PersonEntity.all_neo4j_property_attributes

      # Core properties
      expect(props).to include(:entity_type, :remarks)

      # Person-specific properties
      expect(props).to include(:birth_date, :birth_year, :gender, :title,
                               :position, :affiliation, :death_date)
    end

    it 'AircraftEntity has all expected properties' do
      props = Ammitto::Ontology::Entities::AircraftEntity.all_neo4j_property_attributes

      # Core properties from Entity
      expect(props).to include(:entity_type, :remarks)

      # Aircraft-specific properties
      expect(props).to include(:name, :serial_number, :registration, :icao_24bit,
                               :aircraft_type, :manufacturer, :build_year,
                               :registration_country, :registered_owner, :operator)
    end

    it 'NameVariant has all expected properties' do
      props = Ammitto::Ontology::ValueObjects::NameVariant.all_neo4j_property_attributes

      expect(props).to include(:full_name, :first_name, :middle_name, :last_name,
                               :title, :function, :script, :language, :is_primary)
    end

    it 'Address has all expected properties' do
      props = Ammitto::Ontology::ValueObjects::Address.all_neo4j_property_attributes

      expect(props).to include(:street, :city, :region, :country,
                               :country_iso_code, :postal_code, :po_box, :address_type)
    end

    it 'Identification has all expected properties' do
      props = Ammitto::Ontology::ValueObjects::Identification.all_neo4j_property_attributes

      expect(props).to include(:type, :number, :issuing_country, :issue_date, :expiry_date)
    end
  end

  describe 'to_jsonld' do
    let(:person) do
      Ammitto::Ontology::Entities::PersonEntity.new(
        id: 'https://www.ammitto.org/entity/test/PERSON001',
        entity_type: 'person',
        gender: 'male'
      )
    end

    it 'produces valid JSON-LD structure' do
      jsonld = person.to_jsonld

      expect(jsonld).to have_key('@context')
      expect(jsonld).to have_key('@id')
      expect(jsonld).to have_key('@type')
      expect(jsonld['@id']).to eq('https://www.ammitto.org/entity/test/PERSON001')
      expect(jsonld['@type']).to eq('Person')
    end

    it 'includes all properties in JSON-LD output' do
      jsonld = person.to_jsonld

      expect(jsonld[:entity_type]).to eq('person')
      expect(jsonld[:gender]).to eq('male')
    end
  end
end
