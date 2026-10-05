# frozen_string_literal: true

require 'fileutils'
require 'yaml'

# Shared by the KnowledgeGraphExporter specs that must run the export over
# real input: an empty directory skips every source and proves nothing.
module KnowledgeGraphFixture
  # One DATA_SOURCES entry in the normalized layout the exporter looks for, with a name
  # that carries no script so the loader has to detect it.
  def write_fixture(base_dir)
    processed = File.join(base_dir, 'data-cn', 'processed')
    %w[entities entries].each { |d| FileUtils.mkdir_p(File.join(processed, d)) }
    File.write(File.join(processed, '_index.yaml'), { 'source' => 'cn' }.to_yaml)
    File.write(File.join(processed, 'entities', 'jane-doe.yaml'),
               { 'id' => 'jane-doe', 'entity_type' => 'person',
                 'names' => [{ 'full_name' => 'Jane Doe', 'is_primary' => true }] }.to_yaml)
    File.write(File.join(processed, 'entries', 'entry-jane-doe.yaml'),
               { 'id' => 'jane-doe', 'entity_id' => 'jane-doe',
                 'list_type' => 'asset-freeze', 'status' => 'active' }.to_yaml)
  end
end
