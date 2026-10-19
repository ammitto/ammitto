# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'tmpdir'
require 'json/ld'
require 'json-schema'
require 'ammitto/serialization/ontology_exporter'

RSpec.describe Ammitto::Serialization::OntologyExporter do
  let(:output_dir) { Dir.mktmpdir('ammitto_ontology_test') }
  let(:exporter) { described_class.new }

  after do
    FileUtils.rm_rf(output_dir)
  end

  describe '#export' do
    before do
      exporter.export(output_dir)
    end

    it 'creates ontology directory' do
      expect(Dir.exist?(File.join(output_dir, 'ontology'))).to be true
    end

    it 'creates classes.jsonld' do
      classes_file = File.join(output_dir, 'ontology', 'classes.jsonld')
      expect(File.exist?(classes_file)).to be true

      data = JSON.parse(File.read(classes_file))
      expect(data['@context']).to eq(described_class::METADATA_CONTEXT)
      expect(data['@graph']).to be_an(Array)
      expect(data['@graph'].length).to be > 0
    end

    it 'creates properties.jsonld' do
      properties_file = File.join(output_dir, 'ontology', 'properties.jsonld')
      expect(File.exist?(properties_file)).to be true

      data = JSON.parse(File.read(properties_file))
      expect(data['@context']).to eq(described_class::METADATA_CONTEXT)
      expect(data['@graph']).to be_an(Array)
    end

    it 'expands metadata into RDF classes, properties and IRI-valued links' do
      classes = JSON::LD::API.expand(JSON.parse(File.read(File.join(output_dir, 'ontology/classes.jsonld'))))
      properties = JSON::LD::API.expand(JSON.parse(File.read(File.join(output_dir, 'ontology/properties.jsonld'))))
      person = classes.find { |node| node['@id'].end_with?('/PersonEntity') }
      names = properties.find { |node| node['@id'].end_with?('/names') }
      expect(person['@type']).to eq(['http://www.w3.org/2000/01/rdf-schema#Class'])
      expect(person['http://www.w3.org/2000/01/rdf-schema#subClassOf'])
        .to eq([{ '@id' => "#{described_class::BASE_URI}/Entity" }])
      expect(person['http://www.w3.org/2002/07/owl#equivalentClass'])
        .to eq([{ '@id' => 'https://ammitto.org/schema/v1/PersonEntity' }])
      expect(names['@type']).to eq(['http://www.w3.org/1999/02/22-rdf-syntax-ns#Property'])
      expect(names['http://www.w3.org/2000/01/rdf-schema#range'])
        .to eq([{ '@id' => "#{described_class::BASE_URI}/NameVariant" }])
      expect(names['http://www.w3.org/2000/01/rdf-schema#domain'])
        .to eq([{ '@id' => "#{described_class::BASE_URI}/Entity" }])
      expect(names['http://www.w3.org/2002/07/owl#equivalentProperty'])
        .to eq([{ '@id' => 'https://schema.org/name' }])
    end

    it 'validates examples against ordinary entity contracts and their expanded entry links' do
      schema = JSON.parse(File.read(Ammitto::Serialization::OntologyCatalogue::SCHEMA_PATH))
      %w[person organization vessel].each do |kind|
        example = JSON.parse(File.read(File.join(output_dir, "ontology/examples/#{kind}.jsonld")))
        contract = schema.merge('$ref' => "#/definitions/#{kind.capitalize}Entity")
        expect(JSON::Validator.fully_validate(contract, example)).to be_empty
        expect(example.fetch('names').first['@type']).to eq('NameVariant')
        expect(example.fetch('hasSanctionEntry')).to eq(["https://www.ammitto.org/entry/example/#{kind}"])
        example['@context'] = Ammitto::Schema::Context.context.fetch('@context')
        expanded = JSON::LD::API.expand(example).first
        expect(expanded['https://ammitto.org/schema/v1/hasSanctionEntry'])
          .to eq([{ '@id' => "https://www.ammitto.org/entry/example/#{kind}" }])
      end
      vessel = JSON.parse(File.read(File.join(output_dir, 'ontology/examples/vessel.jsonld')))
      expect(vessel['tonnage']).to eq('@type' => 'Tonnage', 'grossTonnage' => 50_000)
      expect(vessel['imoNumber']).to eq('1234567')
    end

    it 'uses only published class and property names throughout the hierarchy' do
      classes = described_class::CLASSES.map { |item| item[:id] }
      expect(classes).to include('NameVariant', 'Identification', 'Tonnage', 'OfficialAnnouncement', 'SanctionEffect')
      expect(classes & %w[Name Identifier Announcement Measure Country Nationality SanctionsList]).to be_empty
      hierarchy = JSON.parse(File.read(File.join(output_dir, 'ontology/hierarchy.json')))
      names = hierarchy['children'].flat_map { |node| [node['name']] + node.fetch('children').map { |child| child['name'] } }
      expect(names.sort).to eq(classes.sort)
      expect(described_class::PROPERTIES.map { |item| item[:id] } & %w[documents imo flag measures aliases]).to be_empty
    end

    it 'preserves per-class ranges and cardinalities when a shared property varies' do
      properties = JSON.parse(File.read(File.join(output_dir, 'ontology/properties.jsonld')))['@graph']
      authority = properties.find { |property| property['@id'].end_with?('/authority') }
      expect(authority['usages']).to include(
        { 'class' => "#{described_class::BASE_URI}/SanctionEntry", 'range' => "#{described_class::BASE_URI}/Authority", 'isArray' => false },
        { 'class' => "#{described_class::BASE_URI}/OfficialAnnouncement", 'range' => 'http://www.w3.org/2001/XMLSchema#string', 'isArray' => false }
      )
      name = properties.find { |property| property['@id'].end_with?('/name') }
      expect(name['usages']).to include(
        { 'class' => "#{described_class::BASE_URI}/Authority", 'range' => 'http://www.w3.org/2001/XMLSchema#string', 'isArray' => false },
        { 'class' => "#{described_class::BASE_URI}/DocumentType", 'range' => "#{described_class::BASE_URI}/LocalizedString", 'isArray' => true }
      )
      expanded = JSON::LD::API.expand(JSON.parse(File.read(File.join(output_dir, 'ontology/properties.jsonld'))))
      expanded_authority = expanded.find { |property| property['@id'].end_with?('/authority') }
      expect(expanded_authority["#{described_class::BASE_URI}/usages"].first['@type']).to eq('@json')
    end

    # The ontology browser and the JSON-LD context describe the same
    # fields to the same reader (under different bases, so they are not
    # literally one RDF property). Telling that reader "integer" in one
    # and "gYear" in the other is a contradiction, so the year-valued
    # BirthInfo properties are gYear in both, and the date-valued ones
    # are date in both for the same reason.
    describe 'the BirthInfo temporal properties' do
      let(:properties) do
        file = File.join(output_dir, 'ontology', 'properties.jsonld')
        JSON.parse(File.read(file))['@graph']
      end

      def range_of(id)
        properties.find { |p| p['@id'].to_s.end_with?("/#{id}") }&.fetch('range')
      end

      it 'publishes both year range bounds as gYear' do
        expect(range_of('yearRangeFrom'))
          .to eq('http://www.w3.org/2001/XMLSchema#gYear')
        expect(range_of('yearRangeTo'))
          .to eq('http://www.w3.org/2001/XMLSchema#gYear')
      end

      it 'publishes both date range bounds as xsd:date' do
        expect(range_of('dateRangeFrom'))
          .to eq('http://www.w3.org/2001/XMLSchema#date')
        expect(range_of('dateRangeTo'))
          .to eq('http://www.w3.org/2001/XMLSchema#date')
      end

      it 'agrees with the context on the year datatype' do
        context_type =
          Ammitto::Schema::Context.context['@context']['year']['@type']

        expect(context_type).to eq('xsd:gYear')
        expect(range_of('year'))
          .to eq('http://www.w3.org/2001/XMLSchema#gYear')
      end

      it 'lists all four range bounds among the BirthInfo class properties' do
        file = File.join(output_dir, 'ontology', 'classes.jsonld')
        birth = JSON.parse(File.read(file))['@graph']
                    .find { |c| c['@id'].to_s.end_with?('/BirthInfo') }

        expect(birth['properties'])
          .to include('https://www.ammitto.org/ontology/dateRangeFrom',
                      'https://www.ammitto.org/ontology/dateRangeTo',
                      'https://www.ammitto.org/ontology/yearRangeFrom',
                      'https://www.ammitto.org/ontology/yearRangeTo')
      end
    end

    it 'creates hierarchy.json' do
      hierarchy_file = File.join(output_dir, 'ontology', 'hierarchy.json')
      expect(File.exist?(hierarchy_file)).to be true

      data = JSON.parse(File.read(hierarchy_file))
      expect(data['name']).to eq('AmmittoOntology')
      expect(data['children']).to be_an(Array)
    end

    it 'creates examples directory' do
      expect(Dir.exist?(File.join(output_dir, 'ontology', 'examples'))).to be true
    end

    it 'creates example entity files' do
      examples_dir = File.join(output_dir, 'ontology', 'examples')
      expect(File.exist?(File.join(examples_dir, 'person.jsonld'))).to be true
      expect(File.exist?(File.join(examples_dir, 'organization.jsonld'))).to be true
      expect(File.exist?(File.join(examples_dir, 'vessel.jsonld'))).to be true
    end
  end

  describe 'CLASSES' do
    it 'contains Entity class' do
      entity_class = described_class::CLASSES.find { |c| c[:id] == 'Entity' }
      expect(entity_class).not_to be_nil
      expect(entity_class[:label]).to eq('Entity')
    end

    it 'contains PersonEntity as subclass of Entity' do
      person_class = described_class::CLASSES.find { |c| c[:id] == 'PersonEntity' }
      expect(person_class).not_to be_nil
      expect(person_class[:parent]).to eq('Entity')
    end

    it 'contains all expected entity types' do
      ids = described_class::CLASSES.map { |c| c[:id] }
      expect(ids).to include('Entity', 'PersonEntity', 'OrganizationEntity', 'VesselEntity', 'AircraftEntity')
    end
  end

  describe 'PROPERTIES' do
    it 'contains hasSanctionEntry property' do
      prop = described_class::PROPERTIES.find { |p| p[:id] == 'hasSanctionEntry' }
      expect(prop).not_to be_nil
      expect(prop[:domain]).to eq('Entity')
      expect(prop[:range]).to eq('SanctionEntry')
    end

    it 'contains authority property' do
      prop = described_class::PROPERTIES.find { |p| p[:id] == 'authority' }
      expect(prop).not_to be_nil
      expect(prop[:domain]).to be_nil
      expect(prop[:range]).to be_nil
    end

    it 'contains status property' do
      prop = described_class::PROPERTIES.find { |p| p[:id] == 'status' }
      expect(prop).not_to be_nil
      expect(prop[:domain]).to eq('SanctionEntry')
      expect(prop[:range]).to be_nil # status is vocabulary-coerced to an IRI
    end
  end

  describe 'ENTITY_TYPES' do
    it 'contains all four entity types' do
      expect(described_class::ENTITY_TYPES.keys).to include('person', 'organization', 'vessel', 'aircraft')
    end
  end

  describe '#initialize with entity counts' do
    it 'accepts entity counts parameter' do
      counts = { 'person' => 1000, 'organization' => 500 }
      exporter_with_counts = described_class.new(counts)
      # entity_counts is used internally for hierarchy
      expect(exporter_with_counts).to be_a(described_class)
    end
  end
end
