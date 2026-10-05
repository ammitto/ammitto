# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

# `require 'ammitto'` no longer loads the exporter, and RSpec has already
# loaded the whole tree, so the file is used alone in a fresh process. The
# exporter rescues per-source failures into `errors`, so the check is that
# real entities came out and no error was recorded.
RSpec.describe 'Ammitto::Exporter::KnowledgeGraphExporter standalone use' do
  include IsolatedLoadHelper
  include KnowledgeGraphFixture

  it 'exports a fixture source after requiring only its own file' do
    Dir.mktmpdir do |dir|
      write_fixture(dir)
      out = File.join(dir, 'out')
      ok, err = load_in_subprocess(
        'ammitto/exporter/knowledge_graph_exporter',
        "r = Ammitto::Exporter::KnowledgeGraphExporter.new('#{dir}', output_dir: '#{out}').export_all; " \
        'exit(r[:errors].empty? && r[:total_entities] == 1 ? 0 : (warn(r.inspect); 1))'
      )

      expect(ok).to be(true), "standalone export failed:\n#{err}"
      expect(File.exist?(File.join(out, 'stats.json'))).to be(true)
    end
  end
end
