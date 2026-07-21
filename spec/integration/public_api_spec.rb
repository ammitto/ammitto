# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'json'

# Smoke protection for the documented public API: these entry points shipped
# broken in 1.0.0 because nothing exercised them.
RSpec.describe 'public API (integration)' do
  around do |example|
    Dir.mktmpdir do |dir|
      original = Ammitto.configuration.cache_dir
      Ammitto.configure { |c| c.cache_dir = dir }
      @cache_dir = dir
      example.run
    ensure
      Ammitto.configure { |c| c.cache_dir = original }
    end
  end

  def seed_cache(entities)
    sources_dir = File.join(@cache_dir, 'cache', 'sources')
    FileUtils.mkdir_p(sources_dir)
    File.write(File.join(sources_dir, 'eu.jsonld'),
               JSON.generate({ '@graph' => entities }))
  end

  let(:person) do
    {
      '@id' => 'https://www.ammitto.org/entity/eu/1',
      '@type' => 'PersonEntity',
      'entityType' => 'person',
      'names' => [{ 'fullName' => 'Kim Jong Un', 'isPrimary' => true }]
    }
  end

  it 'searches the cache and builds populated models from camelCase JSON-LD' do
    seed_cache([person])

    results = Ammitto.search('Kim', sources: [:eu])
    expect(results).to be_a(Ammitto::Search::ResultSet)
    expect(results.count).to eq(1)
    expect(results.first).to be_a(Ammitto::PersonEntity)
    expect(results.first.names.first.full_name).to eq('Kim Jong Un')
  end

  it 'returns an empty page rather than crashing past the last result' do
    seed_cache([person])

    expect(Ammitto.search('Kim', sources: [:eu], offset: 99).count).to eq(0)
  end

  it 'reports cache status without raising' do
    expect(Ammitto.cache_status).to be_a(Hash)
  end

  it 'exposes every advertised entry point' do
    expect(Ammitto).to respond_to(:search, :refresh_cache, :cache_status,
                                  :sources, :schema, :data_repository)
  end

  it 'registers every source the gem advertises' do
    require 'ammitto/config/defaults'
    expect(Ammitto.sources.sort)
      .to eq(Ammitto::Config::Defaults::ALL_SOURCES.sort)
  end
end
