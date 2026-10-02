# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'ammitto/extractors/registry'

RSpec.describe Ammitto::Extractors::Registry do
  # An extractor directory holding one file that exists but cannot load:
  # its own require names a library that is not installed.
  let(:extractor_dir) do
    Dir.mktmpdir.tap do |dir|
      File.write(File.join(dir, 'jp_extractor.rb'),
                 "require 'ammitto_spec_library_that_is_not_installed'\n")
    end
  end

  before { stub_const("#{described_class}::EXTRACTOR_DIR", extractor_dir) }
  after { FileUtils.remove_entry(extractor_dir) }

  around do |example|
    registered = described_class.instance_variable_get(:@extractors)
    described_class.instance_variable_set(:@extractors, registered.except(:au, :jp))
    example.run
  ensure
    described_class.instance_variable_set(:@extractors, registered)
  end

  describe 'EXTRACTORS' do
    # A source missing from the list reads as having no extractor, so the
    # list has to track the files.
    it 'names every source extractor file in lib/ammitto/extractors' do
      dir = File.expand_path('../../../lib/ammitto/extractors', __dir__)
      codes = Dir[File.join(dir, '*_extractor.rb')].map { |f| File.basename(f, '_extractor.rb').to_sym }

      expect(described_class::EXTRACTORS).to match_array(codes - [:base])
    end
  end

  describe '.exists?' do
    it 'is false for a source whose extractor file is absent' do
      expect(described_class.exists?(:au)).to be(false)
    end

    it 'is false for an unknown source' do
      expect(described_class.exists?(:no_such_source)).to be(false)
    end

    it 'is false for a code that names a path rather than a source' do
      expect(described_class.exists?('../extractors/jp')).to be(false)
    end

    it 'lets a LoadError raised inside an existing extractor file propagate' do
      expect { described_class.exists?(:jp) }
        .to raise_error(LoadError, /ammitto_spec_library_that_is_not_installed/)
    end
  end

  describe '.get' do
    it 'is nil for a source whose extractor file is absent' do
      expect(described_class.get(:au)).to be_nil
    end

    it 'is nil for an unknown source' do
      expect(described_class.get(:no_such_source)).to be_nil
    end

    it 'lets a LoadError raised inside an existing extractor file propagate' do
      expect { described_class.get(:jp) }
        .to raise_error(LoadError, /ammitto_spec_library_that_is_not_installed/)
    end
  end
end
