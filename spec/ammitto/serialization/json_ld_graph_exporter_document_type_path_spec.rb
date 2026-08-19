# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'ammitto/serialization/json_ld_graph_exporter'

# Organizations, instruments and document types all turn a source-supplied
# identifier into a path component. Two of the three refused a component
# the filesystem would answer differently on Linux and Windows; document
# types handed it over. Latent rather than live when this was written —
# 0 unsafe basenames across the 36 document-type files a current harmonize
# emits — which is the moment to close it.
RSpec.describe Ammitto::Serialization::JsonLdGraphExporter do
  let(:output_dir) { Dir.mktmpdir('ammitto_doctype_path') }
  let(:exporter) do
    described_class.new(output_dir: output_dir,
                        context_url: 'https://www.ammitto.org/ontology/context.jsonld')
  end

  after { FileUtils.rm_rf(output_dir) }

  def with_document_type(id)
    exporter.document_types[id] = { '@id' => id, '@type' => 'DocumentType' }
    exporter.send(:export_document_type_nodes)
  end

  it 'refuses a local id holding a question mark' do
    # The corpus case behind the rule: `?` writes happily on Linux and
    # raises Errno::EINVAL on Windows, so the same export succeeded or
    # failed depending on the runner.
    id = 'https://www.ammitto.org/document-type/un/what?'

    expect { with_document_type(id) }
      .to raise_error(Ammitto::Error, /unusable path component "what\?"/)
  end

  it 'refuses a local id that would climb out of the node tree' do
    id = 'https://www.ammitto.org/document-type/un/..'

    expect { with_document_type(id) }
      .to raise_error(Ammitto::Error, /unusable path component/)
  end

  it 'writes an ordinary document type where it always did' do
    id = 'https://www.ammitto.org/document-type/un/resolution'

    with_document_type(id)

    expect(File.file?(File.join(output_dir, 'node', 'document-type', 'un',
                                'resolution.jsonld'))).to be true
  end

  it 'writes one with no recognised source at the top level' do
    id = 'https://www.ammitto.org/document-type/decision'

    with_document_type(id)

    expect(File.file?(File.join(output_dir, 'node', 'document-type',
                                'decision.jsonld'))).to be true
  end
end
