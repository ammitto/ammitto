# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'
require 'yaml'
require 'spec_helper'
require 'ammitto/cli/harmonize_command'
require 'ammitto/data/knowledge_graph_loader'

RSpec.describe Ammitto::Data::KnowledgeGraphLoader do
  let(:root_dir) { Dir.mktmpdir('ammitto_loader_collision') }
  let(:source_dir) { File.join(root_dir, 'loader', 'data-ca', 'processed') }
  let(:harmonize_source_dir) { File.join(root_dir, 'harmonize', 'data-ca', 'processed') }
  let(:output_dir) { File.join(root_dir, 'output') }
  # Two ids sharing their first 64 characters, the IRI id length limit.
  let(:ids) { ["#{'a' * 64}1", "#{'a' * 64}2"] }

  before do
    ids.each do |id|
      write_yaml(harmonize_source_dir, "#{id}.yml", source_record(id))
      write_yaml(File.join(source_dir, 'entities'), "#{id}.yaml", entity_record(id))
      write_yaml(File.join(source_dir, 'entries'), "#{id}.yaml", entry_record(id))
    end
  end

  after { FileUtils.remove_entry(root_dir) }

  it 'matches harmonize digest IRIs for entities and entries' do
    Ammitto::Cmd::HarmonizeCommand.new(
      { sources_dir: File.join(root_dir, 'harmonize'), output_dir: output_dir, combine: false },
      ['ca']
    ).run

    harmonized_graph = JSON.parse(
      File.read(File.join(output_dir, 'sources', 'ca.jsonld'))
    )['@graph']
    harmonized_entity_iris = harmonized_graph.filter_map do |node|
      node['@id'] if node['@id'].include?('/entity/')
    end
    harmonized_entry_iris = harmonized_graph.filter_map do |node|
      node['@id'] if node['@id'].include?('/entry/')
    end

    harmonized = described_class.new(source_dir).to_harmonized

    expect(harmonized[:entities].map { |entity| entity['id'] })
      .to match_array(harmonized_entity_iris)
    expect(harmonized[:entries].map { |entry| entry['id'] })
      .to match_array(harmonized_entry_iris)
    expect(harmonized[:entries].map { |entry| entry['entity_id'] })
      .to match_array(harmonized_entity_iris)
  end

  it 'digests colliding entity records but not an orphan entity reference' do
    orphan_entity_id = "#{'a' * 64}3"
    write_yaml(File.join(source_dir, 'entries'), 'orphan.yaml',
               entry_record('orphan').merge('entity_id' => orphan_entity_id))

    harmonized = described_class.new(source_dir).to_harmonized
    orphan = harmonized[:entries].find { |entry| entry['id'].end_with?('/orphan') }

    plain_cut = "https://www.ammitto.org/entity/ca/#{'a' * 64}"
    entity_iris = harmonized[:entities].map { |entity| entity['id'] }

    expect(entity_iris.uniq.size).to eq(2)
    expect(entity_iris).not_to include(plain_cut)
    expect(orphan['entity_id']).to eq(plain_cut)
  end

  private

  def write_yaml(dir, filename, data)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, filename), data.to_yaml)
  end

  def source_record(id)
    {
      'country' => id,
      'entity_type' => 'organization',
      'entity_or_ship' => "Entity #{id}",
      'schedule' => nil,
      'item' => nil
    }
  end

  def entity_record(id)
    {
      'id' => id,
      'entity_type' => 'organization',
      'names' => [{ 'full_name' => "Entity #{id}", 'is_primary' => true }]
    }
  end

  def entry_record(id)
    {
      'id' => id,
      'entity_id' => id,
      'list_type' => 'consolidated-list',
      'status' => 'active'
    }
  end
end
