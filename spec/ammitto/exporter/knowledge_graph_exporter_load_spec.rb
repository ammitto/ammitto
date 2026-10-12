# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

# `require 'ammitto'` has already run by the time an example does, so both
# checks use a fresh process.
RSpec.describe 'Ammitto::Exporter::KnowledgeGraphExporter loading' do
  include IsolatedLoadHelper
  include KnowledgeGraphFixture

  # SimpleExporter and JsonLdExport minted ammitto.org IRIs from a lossy slug,
  # outside the collision registry the harmonize path uses.
  it "is not defined by require 'ammitto', nor are the removed exporters" do
    ok, err = load_in_subprocess(
      'ammitto',
      'loaded = %w[KnowledgeGraphExporter SimpleExporter JsonLdExport].select { |c| ' \
      'defined?(Ammitto::Exporter) && Ammitto::Exporter.const_defined?(c, false) }; ' \
      'abort(loaded.join(", ")) unless loaded.empty?'
    )

    expect(ok).to be(true), "require 'ammitto' defined an exporter:\n#{err}"
  end

  it 'loads when required explicitly' do
    ok, err = load_in_subprocess(
      'ammitto/exporter/knowledge_graph_exporter',
      'exit(Ammitto::Exporter::KnowledgeGraphExporter ? 0 : 1)'
    )

    expect(ok).to be(true), "explicit require failed:\n#{err}"
  end

  it 'still runs scripts/export_knowledge_graph.rb' do
    script = File.expand_path('../../../scripts/export_knowledge_graph.rb', __dir__)

    Dir.mktmpdir do |dir|
      write_fixture(dir)
      out = File.join(dir, 'out')
      err_path = File.join(dir, 'script.err')
      ok = system(RbConfig.ruby, script, dir, out,
                  out: File::NULL, err: err_path)

      expect(ok).to be(true), "script failed:\n#{File.read(err_path)}"
      expect(JSON.parse(File.read(File.join(out, 'stats.json')))['total_entities']).to eq(1)
    end
  end
end
