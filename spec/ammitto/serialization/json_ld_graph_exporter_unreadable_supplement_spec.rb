# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'ammitto/serialization/json_ld_graph_exporter'

# Writes a supplement file whose YAML cannot be parsed, and builds an
# exporter over it.
module UnreadableSupplementHelpers
  def write_unreadable(dir, name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, name), "key: [unclosed\n")
  end

  def build(**dirs)
    Ammitto::Serialization::JsonLdGraphExporter.new(output_dir: output_dir, **dirs)
  end
end

RSpec.describe Ammitto::Serialization::JsonLdGraphExporter do
  include UnreadableSupplementHelpers

  let(:output_dir) { Dir.mktmpdir('ammitto_unreadable_out') }
  let(:root) { Dir.mktmpdir('ammitto_unreadable_supplement') }
  let(:supporting) { File.join(root, 'supporting') }
  let(:instruments) { File.join(root, 'legal-instruments') }

  around do |example|
    verbose = ENV.delete('VERBOSE')
    example.run
  ensure
    ENV['VERBOSE'] = verbose if verbose
  end

  after do
    FileUtils.rm_rf(output_dir)
    FileUtils.rm_rf(root)
  end

  it 'reports an unreadable legal instrument file in a default run' do
    write_unreadable(instruments, 'law.yml')

    expect { build(instruments_dir: instruments) }
      .to output(/Could not load instrument .*law\.yml/).to_stderr
  end

  it 'reports an unreadable document types file in a default run' do
    write_unreadable(supporting, 'document-types.yml')

    expect { build(supporting_dir: supporting) }
      .to output(/Could not load document types .*document-types\.yml/).to_stderr
  end

  it 'reports an unreadable organizations file in a default run' do
    write_unreadable(supporting, 'organizations.yml')

    expect { build(supporting_dir: supporting) }
      .to output(/Could not load organizations .*organizations\.yml/).to_stderr
  end
end
