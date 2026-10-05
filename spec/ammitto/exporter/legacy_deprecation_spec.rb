# frozen_string_literal: true

require 'spec_helper'
require 'logger'
require 'stringio'

module LegacyDeprecationHelpers
  def deprecation_log
    io.string
  end
end

RSpec.describe Ammitto::Exporter::LegacyDeprecation do
  include LegacyDeprecationHelpers

  let(:io) { StringIO.new }

  before do
    described_class.send(:reset!)
    Ammitto::Logger.logger = Logger.new(io)
  end

  after do
    Ammitto::Logger.logger = nil
    described_class.send(:reset!)
  end

  [Ammitto::Exporter::SimpleExporter, Ammitto::Exporter::JsonLdExport].each do |klass|
    describe klass.name do
      it 'warns once per process, however many instances are built' do
        3.times { klass.new(base_dir: Dir.tmpdir) }

        expect(deprecation_log.scan(klass.name).length).to eq(1)
      end

      it 'names the CLI replacement and the removal release' do
        klass.new(base_dir: Dir.tmpdir)

        expect(deprecation_log).to include('deprecated', 'ammitto harmonize', 'ammitto export', '2.0')
      end
    end
  end

  it 'warns once when many threads make the first use at the same time' do
    klass = Ammitto::Exporter::SimpleExporter
    gate = Queue.new
    threads = Array.new(8) do
      Thread.new do
        gate.pop
        klass.new(base_dir: Dir.tmpdir)
      end
    end
    8.times { gate << true }
    threads.each(&:join)

    expect(deprecation_log.scan(klass.name).length).to eq(1)
  end

  it 'is visible at the default logger level' do
    prior = Ammitto.instance_variable_get(:@configuration)
    Ammitto::Logger.logger = nil
    Ammitto.reset_configuration!

    expect { Ammitto::Exporter::JsonLdExport.new(base_dir: Dir.tmpdir) }
      .to output(/WARN: Ammitto::Exporter::JsonLdExport is deprecated/).to_stderr
  ensure
    Ammitto.instance_variable_set(:@configuration, prior)
    Ammitto::Logger.logger = nil
  end

  it 'warns again in a forked process that inherited the parent state' do
    klass = Ammitto::Exporter::SimpleExporter
    klass.new(base_dir: Dir.tmpdir)
    allow(Process).to receive(:pid).and_return(Process.pid + 1)
    klass.new(base_dir: Dir.tmpdir)

    expect(deprecation_log.scan(klass.name).length).to eq(2)
  end

  it 'tracks each exporter separately' do
    Ammitto::Exporter::SimpleExporter.new(base_dir: Dir.tmpdir)
    Ammitto::Exporter::JsonLdExport.new(base_dir: Dir.tmpdir)

    expect(deprecation_log).to include('SimpleExporter', 'JsonLdExport')
  end
end
