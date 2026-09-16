# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'json'

# aggregate_to_site.rb derives every path from its own location
# (`AMMITTO_ROOT = Pathname.new(__dir__).parent`) and only runs its
# aggregation when invoked as the main program, so it cannot be required
# and driven in-process against fixture data. Instead each example copies
# the real script into a fake root, builds sibling data-*/ and
# ammitto.github.io/ directories next to it, and runs it as a subprocess
# — the same isolation reason spec/support/isolated_load_helper.rb gives
# for the source isolated_load specs.
RSpec.describe 'scripts/aggregate_to_site.rb' do
  let(:root) { Dir.mktmpdir('aggregate_to_site_spec') }
  let(:ammitto_root) { File.join(root, 'ammitto') }
  let(:site_api_dir) do
    File.join(root, 'ammitto.github.io', 'api', 'v1')
  end

  before do
    FileUtils.mkdir_p(File.join(ammitto_root, 'scripts'))
    FileUtils.cp(
      File.expand_path('../../scripts/aggregate_to_site.rb', __dir__),
      File.join(ammitto_root, 'scripts', 'aggregate_to_site.rb')
    )
  end

  after { FileUtils.rm_rf(root) }

  def run_script
    system(
      RbConfig.ruby,
      File.join(ammitto_root, 'scripts', 'aggregate_to_site.rb'),
      out: File::NULL, err: File::NULL
    )
  end

  def write_shard(data_dir, code, entities)
    search_index_dir = File.join(root, data_dir, 'api', 'search-index')
    FileUtils.mkdir_p(search_index_dir)
    File.write(
      File.join(search_index_dir, "#{code}.json"),
      JSON.generate(
        { metadata: { totalEntities: entities.length, sources: 1 },
          entities: entities }
      )
    )
    File.write(
      File.join(search_index_dir, 'manifest.json'),
      JSON.generate(
        { metadata: { totalEntities: entities.length, sources: 1 },
          shards: [{ code: code, file: "#{code}.json",
                     count: entities.length }] }
      )
    )
  end

  it 'combines every authority shard into one search index' do
    write_shard('data-au', 'au', [{ 'id' => 'au/1' }, { 'id' => 'au/2' }])

    expect(run_script).to be true

    combined = JSON.parse(File.read(File.join(site_api_dir, 'search-index.json')))
    expect(combined['entities'].map { |e| e['id'] }).to contain_exactly('au/1', 'au/2')
    expect(combined['metadata']['totalEntities']).to eq(2)
  end

  it 'raises instead of silently writing an empty index when a source has no sharded output' do
    # api/ exists (so the source is not skipped outright) but carries
    # neither the old monolithic search-index.json nor the new
    # search-index/ directory this PR's exporter produces.
    FileUtils.mkdir_p(File.join(root, 'data-au', 'api'))

    expect(run_script).to be false
    expect(File.exist?(File.join(site_api_dir, 'search-index.json'))).to be false
  end
end
