# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'rdf/turtle'
require 'ammitto/serialization/turtle_exporter'

RSpec.describe Ammitto::Serialization::TurtleExporter do
  def parsed_literals(node, predicate)
    Dir.mktmpdir('ammitto-turtle-escaping') do |dir|
      input = File.join(dir, 'input.jsonld')
      output = File.join(dir, 'output.ttl')
      original_json = JSON.pretty_generate(node)
      File.write(input, original_json)

      described_class.export(jsonld_path: input, output_path: output)

      expect(File.read(input)).to eq(original_json)
      expect(JSON.parse(File.read(input))).to eq(node)
      values = []
      RDF::Turtle::Reader.open(output, validate: true, logger: false) do |reader|
        reader.each_statement do |statement|
          values << statement.object.to_s if statement.predicate.to_s == predicate
        end
      end
      values
    end
  end

  it 'preserves the literal backslash in the published UK bel0057 birthplace' do
    city = 'village Privalki \Privalka in Hrodna/Grodno Oblast'
    node = {
      '@context' => 'https://ammitto.org/api/v1/context.jsonld',
      '@id' => 'https://www.ammitto.org/entity/uk/bel0057',
      '@type' => 'PersonEntity', 'entityType' => 'person',
      'names' => [{ '@type' => 'NameVariant', 'fullName' => 'Tertel', 'firstName' => 'Ivan' }],
      'birthInfo' => [{ '@type' => 'BirthInfo', 'date' => '1966-09-08', 'circa' => false,
                        'year' => 1966, 'city' => city, 'country' => 'Former USSR Currently Belarus' }]
    }

    expect(parsed_literals(node, 'https://www.ammitto.org/ontology/city')).to eq([city])
  end

  {
    'literal backslash-n' => 'literal\n',
    'literal backslash-t' => 'literal\t',
    'Windows-style backslashes' => 'C:\temp\new\file',
    'backslash before a quote' => 'slash-before-quote: \"',
    'two consecutive backslashes' => 'two slashes: \\\\',
    'actual newline, carriage return and tab' => "line\nbreak\rreturn\ttab",
    'quoted text' => 'quoted "text"',
    'Unicode text' => 'Беларусь'
  }.each do |label, text|
    it "preserves #{label} through strict Turtle parsing" do
      node = { '@id' => 'https://www.ammitto.org/entity/uk/escaping',
               '@type' => 'PersonEntity', 'remarks' => text }

      expect(parsed_literals(node, 'https://www.ammitto.org/ontology/remarks')).to eq([text])
    end
  end
end
