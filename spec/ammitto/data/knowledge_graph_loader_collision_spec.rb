# frozen_string_literal: true

require 'digest'
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

  it 'digests colliding announcement and legal instrument ids and their references' do
    ids.each do |id|
      write_yaml(File.join(source_dir, 'announcements'), "#{id}.yaml", { 'id' => id })
      write_yaml(File.join(source_dir, 'legal_instruments'), "#{id}.yaml", { 'id' => id })
      write_yaml(File.join(source_dir, 'entries'), "#{id}.yaml",
                 entry_record(id).merge('announcement_id' => id, 'legal_instrument_ids' => [id]))
    end

    harmonized = described_class.new(source_dir).to_harmonized
    announcement_iris = harmonized[:announcements].map { |announcement| announcement['id'] }
    instrument_iris = harmonized[:legal_instruments].map { |instrument| instrument['id'] }

    expect(announcement_iris.uniq.size).to eq(2)
    expect(announcement_iris).not_to include("https://www.ammitto.org/announcement/ca/#{'a' * 64}")
    expect(instrument_iris.uniq.size).to eq(2)
    expect(instrument_iris).not_to include("https://www.ammitto.org/legal_instrument/ca/#{'a' * 64}")
    expect(harmonized[:entries].map { |entry| entry['announcement_id'] })
      .to match_array(announcement_iris)
    expect(harmonized[:entries].flat_map { |entry| entry['legal_instrument_ids'] })
      .to match_array(instrument_iris)
  end

  it 'counts announcement and legal instrument ids cited without a record of their own' do
    stored_id, cited_id = ids
    write_yaml(File.join(source_dir, 'announcements'), "#{stored_id}.yaml", { 'id' => stored_id })
    write_yaml(File.join(source_dir, 'legal_instruments'), "#{stored_id}.yaml", { 'id' => stored_id })
    write_yaml(File.join(source_dir, 'entries'), "#{cited_id}.yaml",
               entry_record(cited_id).merge('announcement_id' => cited_id))
    write_yaml(File.join(source_dir, 'lists'), 'consolidated-list.yaml',
               { 'id' => 'consolidated-list', 'legal_instrument_ids' => [cited_id] })

    harmonized = described_class.new(source_dir).to_harmonized
    announcement_iri = harmonized[:announcements].first['id']
    instrument_iri = harmonized[:legal_instruments].first['id']
    cited_announcement_iri = harmonized[:entries].find { |entry| entry['announcement_id'] }['announcement_id']
    cited_instrument_iri = harmonized[:lists].first['legal_instrument_ids'].first

    expect(announcement_iri).to eq("https://www.ammitto.org/announcement/ca/#{digest_id(stored_id)}")
    expect(cited_announcement_iri).to eq("https://www.ammitto.org/announcement/ca/#{digest_id(cited_id)}")
    expect(instrument_iri).to eq("https://www.ammitto.org/legal_instrument/ca/#{digest_id(stored_id)}")
    expect(cited_instrument_iri).to eq("https://www.ammitto.org/legal_instrument/ca/#{digest_id(cited_id)}")
  end

  private

  def digest_id(id)
    sanitizer = Ammitto::Utils::IriSanitizer
    head = id[0, sanitizer::MAX_ID_LENGTH - sanitizer::DIGEST_LENGTH - 1]
    "#{head}-#{Digest::SHA256.hexdigest(id)[0, sanitizer::DIGEST_LENGTH]}"
  end

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
