# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'ammitto/serialization/json_ld_graph_exporter'
require 'ammitto/extractors/us_extractor'

RSpec.describe 'Verbose output through Ammitto.configuration' do
  include VerboseEnvironmentHelper

  let(:output_dir) { Dir.mktmpdir('ammitto_verbose_out') }
  let(:exporter) { Ammitto::Serialization::JsonLdGraphExporter.new(output_dir: output_dir) }
  let(:extractor) { Ammitto::Extractors::UsExtractor.new }

  after { FileUtils.rm_rf(output_dir) }

  describe 'which variables switch it on' do
    it 'is off when neither variable is set' do
      with_verbose_env { expect(Ammitto.configuration.verbose).to be(false) }
    end

    it 'turns on for AMMITTO_VERBOSE=true' do
      with_verbose_env('AMMITTO_VERBOSE' => 'true') do
        expect(Ammitto.configuration.verbose).to be(true)
      end
    end

    it 'turns on for the legacy VERBOSE variable' do
      with_verbose_env('VERBOSE' => '1') do
        expect(Ammitto.configuration.verbose).to be(true)
      end
    end

    it 'lets AMMITTO_VERBOSE=false win over the legacy variable' do
      with_verbose_env('AMMITTO_VERBOSE' => 'false', 'VERBOSE' => '1') do
        expect(Ammitto.configuration.verbose).to be(false)
      end
    end

    it 'keeps an empty AMMITTO_VERBOSE in charge over the legacy variable' do
      with_verbose_env('AMMITTO_VERBOSE' => '', 'VERBOSE' => '1') do
        expect(Ammitto.configuration.verbose).to be(false)
      end
    end

    it 'turns on for an empty legacy VERBOSE, since being set is enough' do
      with_verbose_env('VERBOSE' => '') do
        expect(Ammitto.configuration.verbose).to be(true)
      end
    end
  end

  describe 'the spec helper' do
    it 'puts back the configuration that was in place, not a fresh one' do
      Ammitto.configure { |config| config.cache_dir = '/tmp/ammitto-prior-cache' }
      before = Ammitto.configuration

      with_verbose_env('VERBOSE' => '1') { Ammitto.configuration }

      expect([Ammitto.configuration.equal?(before), Ammitto.configuration.cache_dir])
        .to eq([true, '/tmp/ammitto-prior-cache'])
    ensure
      Ammitto.reset_configuration!
    end
  end

  describe 'the export summary' do
    it 'prints under AMMITTO_VERBOSE' do
      with_verbose_env('AMMITTO_VERBOSE' => 'true') do
        expect { exporter.export }.to output(/Exported 0 entities/).to_stdout
      end
    end

    it 'prints under the legacy VERBOSE' do
      with_verbose_env('VERBOSE' => '1') do
        expect { exporter.export }.to output(/Exported 0 entities/).to_stdout
      end
    end

    it 'stays silent when verbose is off' do
      with_verbose_env { expect { exporter.export }.not_to output.to_stdout }
    end

    it 'follows a configuration assignment made without any variable' do
      with_verbose_env do
        Ammitto.configure { |config| config.verbose = true }

        expect { exporter.export }.to output(/Exported 0 entities/).to_stdout
      end
    end
  end

  describe 'an extractor' do
    before do
      allow(Ammitto::Extractors::HttpClient).to receive(:get).and_return('<sdnList/>')
    end

    it 'reports progress under the legacy VERBOSE' do
      with_verbose_env('VERBOSE' => '1') do
        expect { extractor.fetch }.to output(/Downloading SDN list/).to_stdout
      end
    end

    it 'follows a configuration assignment made without any variable' do
      with_verbose_env do
        Ammitto.configure { |config| config.verbose = true }

        expect { extractor.fetch }.to output(/Downloading SDN list/).to_stdout
      end
    end

    it 'stays silent when verbose is off' do
      with_verbose_env { expect { extractor.fetch }.not_to output.to_stdout }
    end
  end
end
