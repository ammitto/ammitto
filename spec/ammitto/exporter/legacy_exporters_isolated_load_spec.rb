# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'yaml'

# The first `.new` reaches Logger and Ammitto.configuration, which only
# `require 'ammitto'` loads for free. RSpec has already required the whole
# tree, so each file is loaded alone in a fresh process.
RSpec.describe 'Ammitto::Exporter legacy exporter files' do
  include IsolatedLoadHelper

  {
    'ammitto/exporter/simple_exporter' => 'SimpleExporter',
    'ammitto/exporter/json_ld_export' => 'JsonLdExport'
  }.each do |path, klass|
    it "instantiates #{klass} after requiring only #{path}, and warns" do
      ok, err = load_in_subprocess(
        path, "Ammitto::Exporter::#{klass}.new(base_dir: '/tmp')"
      )

      expect(ok).to be(true), "standalone use failed:\n#{err}"
      expect(err).to include("Ammitto::Exporter::#{klass} is deprecated")
    end
  end

  # JsonLdExport is only proven to instantiate here: its export builds
  # lutaml models, which need the runtime that `require 'ammitto'` sets up.
  it 'exports a fixture source with SimpleExporter after requiring only its file' do
    Dir.mktmpdir do |dir|
      processed = File.join(dir, 'eu-data', 'processed')
      FileUtils.mkdir_p(processed)
      File.write(File.join(processed, 'a.yaml'),
                 { 'entity_type' => 'person', 'ref_number' => 'EU.1',
                   'names' => ['Jane Doe'], 'birthDate' => Date.new(1970, 1, 2) }.to_yaml)
      ok, err = load_in_subprocess(
        'ammitto/exporter/simple_exporter',
        "r = Ammitto::Exporter::SimpleExporter.new(base_dir: '#{dir}').export_all; " \
        'exit(r[:eu] == { files: 1, entities: 1 } ? 0 : (warn(r.inspect); 1))'
      )

      expect(ok).to be(true), "standalone export failed:\n#{err}"
      expect(File.exist?(File.join(dir, 'data', 'api', 'v1', 'sources', 'eu.jsonld'))).to be(true)
    end
  end
end
