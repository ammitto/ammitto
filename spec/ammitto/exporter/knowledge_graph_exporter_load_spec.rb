# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

# `require 'ammitto'` has already run by the time an example does, so both
# checks use a fresh process.
RSpec.describe 'Ammitto::Exporter::KnowledgeGraphExporter loading' do
  include IsolatedLoadHelper
  include KnowledgeGraphFixture

  it "is not defined by require 'ammitto'" do
    ok, err = load_in_subprocess(
      'ammitto',
      'exit(Ammitto::Exporter.const_defined?(:KnowledgeGraphExporter, false) ? 1 : 0)'
    )

    expect(ok).to be(true), "require 'ammitto' defined the exporter:\n#{err}"
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
