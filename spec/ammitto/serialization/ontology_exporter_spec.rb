# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'tmpdir'
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
      expect(data['@context']).to eq('https://ammitto.org/api/v1/context.jsonld')
      expect(data['@graph']).to be_an(Array)
      expect(data['@graph'].length).to be > 0
    end

    it 'creates properties.jsonld' do
      properties_file = File.join(output_dir, 'ontology', 'properties.jsonld')
      expect(File.exist?(properties_file)).to be true

      data = JSON.parse(File.read(properties_file))
      expect(data['@context']).to eq('https://ammitto.org/api/v1/context.jsonld')
      expect(data['@graph']).to be_an(Array)
    end

    # The ontology and the JSON-LD context describe the SAME properties.
    # A consumer that reads both must not be told two datatypes for one
    # property, so the year-valued BirthInfo properties are gYear in
    # both places.
    describe 'the BirthInfo year properties' do
      let(:properties) do
        file = File.join(output_dir, 'ontology', 'properties.jsonld')
        JSON.parse(File.read(file))['@graph']
      end

      def range_of(id)
        properties.find { |p| p['@id'].to_s.end_with?("/#{id}") }&.fetch('range')
      end

      it 'publishes both range bounds' do
        expect(range_of('yearRangeFrom'))
          .to eq('http://www.w3.org/2001/XMLSchema#gYear')
        expect(range_of('yearRangeTo'))
          .to eq('http://www.w3.org/2001/XMLSchema#gYear')
      end

      it 'agrees with the context on the year datatype' do
        context_type =
          Ammitto::Schema::Context.context['@context']['year']['@type']

        expect(context_type).to eq('xsd:gYear')
        expect(range_of('year'))
          .to eq('http://www.w3.org/2001/XMLSchema#gYear')
      end

      it 'lists both bounds among the BirthInfo class properties' do
        file = File.join(output_dir, 'ontology', 'classes.jsonld')
        birth = JSON.parse(File.read(file))['@graph']
                    .find { |c| c['@id'].to_s.end_with?('/BirthInfo') }

        expect(birth['properties'])
          .to include('https://www.ammitto.org/ontology/yearRangeFrom',
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
      expect(prop[:domain]).to eq('SanctionEntry')
      expect(prop[:range]).to eq('Authority')
    end

    it 'contains status property' do
      prop = described_class::PROPERTIES.find { |p| p[:id] == 'status' }
      expect(prop).not_to be_nil
      expect(prop[:domain]).to eq('SanctionEntry')
      expect(prop[:range]).to eq('string')
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
