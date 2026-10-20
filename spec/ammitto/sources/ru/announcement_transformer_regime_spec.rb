# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'ammitto/sources/ru'
require 'ammitto/serialization/json_ld_serializer'
require 'ammitto/serialization/json_ld_graph_exporter'
require 'ammitto/validation/output_validator'

RSpec.describe Ammitto::Sources::Ru::AnnouncementTransformer do
  subject(:transformer) { described_class.new }

  around do |example|
    Dir.mktmpdir('ammitto-ru-regime') do |dir|
      @output_dir = dir
      example.run
    end
  end

  def announcement(list)
    party = { 'name' => { 'en' => 'Source Person' }, 'type' => 'individual' }
    party['sanction_list'] = list unless list.nil?
    Ammitto::Sources::Ru::Announcement.from_hash(
      'announcement' => {
        'url' => 'https://www.mid.ru/ru/detail-material-page/1817739/',
        'publish_date' => '2022-08-01'
      },
      'sanction_details' => { 'entities' => [party] }
    )
  end

  def export_announcement(list)
    result = transformer.canonical_transform_announcement(announcement(list))
    serializer = Ammitto::Serialization::JsonLdSerializer.new
    graph = Ammitto::Serialization::JsonLdGraphExporter.new(output_dir: @output_dir)
    graph.add_node(entity: serializer.serialize_entity(result[:entities].first),
                   entry: serializer.serialize_entry(result[:entries].first),
                   source: :ru)
    graph.export(cleanup: false)
    validator = Ammitto::Validation::OutputValidator.new(output_dir: @output_dir)
    validation = validator.validate_files(graph.written_paths.to_a)
    [result[:entries].first, graph, validation]
  end

  [nil, '', '   '].each do |missing|
    it "exports valid output without a regime when the source list is #{missing.inspect}" do
      entry, graph, validation = export_announcement(missing)

      expect(validation.errors).to eq([])
      expect(entry.regime).to be_nil
      expect(entry.id).to include('/entry/ru/unknown/')
      expect(graph.regimes).to be_empty
      expect(File.exist?(File.join(@output_dir, 'node/regime/ru_unknown.jsonld'))).to be(false)
      aggregate = JSON.parse(File.read(File.join(@output_dir, 'all.jsonld')))
      expect(aggregate.fetch('@graph').none? { |node| node['@type'] == 'SanctionRegime' }).to be(true)
    end
  end

  [
    ['черного списка', 'RU_STOP_LIST', 'Стоп-лист (Stop-list)', 'stop-list'],
    ['Source-provided list', 'RU_UNKNOWN', 'Source-provided list', 'unknown']
  ].each do |list, code, name, slug|
    it "retains the named regime and entry list identifier for #{list.inspect}" do
      entry, graph, validation = export_announcement(list)

      expect(validation.errors).to eq([])
      expect(entry.regime.code).to eq(code)
      expect(entry.regime.name).to eq(name)
      expect(entry.id).to include("/entry/ru/#{slug}/")
      expect(graph.regimes.length).to eq(1)
    end
  end
end
