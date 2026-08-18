# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'thor'
require 'tmpdir'
require 'ammitto/cli/harmonize_command'

# ammitto/data recovered these facts by regexing this command's stdout for
# "Harmonize health gate failed:" and two-space-indented rows, which reads
# a raised Thor::Error message as an interface and couples a workflow to
# wording this command is free to change. --report is that interface.
RSpec.describe Ammitto::Cmd::HarmonizeCommand do
  let(:dir) { Dir.mktmpdir('ammitto_report') }
  let(:path) { File.join(dir, 'nested', 'harmonize-report.json') }
  let(:options) { { report: path } }
  let(:command) { described_class.new(options, []) }

  after { FileUtils.rm_rf(dir) }

  def report_for(results)
    command.send(:write_report, results)
    JSON.parse(File.read(path))
  end

  it 'stamps the schema so a consumer can refuse a shape it does not know' do
    report = report_for([{ code: :au, status: :success, entities: 3, entries: 3 }])

    expect(report['schema']).to eq('ammitto-harmonize-report/v1')
  end

  it 'creates the directory the path names' do
    report_for([{ code: :au, status: :success, entities: 1, entries: 1 }])

    expect(File.file?(path)).to be true
  end

  it 'reports a source error as a gate failure with gates_passed false' do
    report = report_for([{ code: :ru, status: :error,
                           error: 'No YAML files found' }])

    expect(report['gates_passed']).to be false
    expect(report['counts']).to eq('succeeded' => 0, 'failed' => 1,
                                   'exempted' => 0)
    entry = report['sources'].first
    expect(entry['code']).to eq('ru')
    expect(entry['error']).to eq('No YAML files found')
    expect(entry['gate_failures']).to eq(['ru: No YAML files found'])
  end

  it 'reports an --allow-empty source as exempted and lets the gates pass' do
    options[:allow_empty] = 'ru'

    report = report_for([{ code: :ru, status: :error,
                           error: 'No YAML files found' }])

    expect(report['gates_passed']).to be true
    expect(report['counts']).to eq('succeeded' => 0, 'failed' => 0,
                                   'exempted' => 1)
    entry = report['sources'].first
    expect(entry['gate_failures']).to be_empty
    expect(entry['exempted_failures']).to eq(['ru: No YAML files found'])
  end

  it 'keeps a per-file transform error failing even for an exempt source' do
    # No exemption clears these, so the report must not file them under
    # exempted_failures where a reader would discount them.
    options[:allow_empty] = 'ch'

    report = report_for([{ code: :ch, status: :success, entities: 3,
                           entries: 3, errors: ['x.yml: boom'] }])

    entry = report['sources'].first
    expect(report['gates_passed']).to be false
    expect(entry['transform_errors']).to eq(['x.yml: boom'])
    expect(entry['exempted_failures']).to be_empty
  end

  it 'agrees with the printed summary on every count' do
    # The counts and the exit code come from one gate evaluation; a report
    # that classified independently could contradict the log beside it.
    # au needs its per-source aggregate on disk or the missing-aggregate
    # gate fails it, which is the gate doing its job, not a fixture bug.
    options[:output_dir] = File.join(dir, 'out')
    FileUtils.mkdir_p(File.join(options[:output_dir], 'sources'))
    aggregate = { '@graph' => [{ '@id' => 'https://www.ammitto.org/entity/au/e1',
                                 'name' => 'Example Pty Ltd' }] }
    File.write(File.join(options[:output_dir], 'sources', 'au.jsonld'),
               JSON.generate(aggregate))
    results = [{ code: :au, status: :success, entities: 5, entries: 5 },
               { code: :ru, status: :error, error: 'No YAML files found' }]

    expect { command.send(:print_summary, results) }
      .to output(/1 succeeded, 1 failed, 0 exempted/).to_stdout
    report = report_for(results)

    expect(report['counts']).to eq('succeeded' => 1, 'failed' => 1,
                                   'exempted' => 0)
  end

  it 'carries a UTC timestamp taken from the run' do
    # Format alone would survive a hardcoded date, so the value has to be
    # pinned to now as well.
    before = Time.now.utc

    report = report_for([{ code: :au, status: :success, entities: 1,
                           entries: 1 }])

    expect(report['generated_at']).to match(/\A\d{4}-\d{2}-\d{2}T[\d:]+Z\z/)
    stamped = Time.parse(report['generated_at'])
    expect(stamped).to be_between(before - 1, Time.now.utc + 1)
  end

  it 'reports an errored source with no count rather than a count of zero' do
    # 0 is a measurement. A source that never read a file did not measure
    # anything, and a consumer charting "entities today" must not be
    # handed a zero it will treat as one.
    report = report_for([{ code: :ru, status: :error,
                           error: 'No YAML files found' }])

    entry = report['sources'].first
    expect(entry['entities']).to be_nil
    expect(entry['entries']).to be_nil
  end

  describe 'a run whose gates fail' do
    before { allow($stdout).to receive(:write) }

    def run_options(report: path)
      sources_dir = File.join(dir, 'sources')
      FileUtils.mkdir_p(File.join(sources_dir, 'data-ru', 'processed'))
      opts = { sources_dir: sources_dir, output_dir: File.join(dir, 'out') }
      report ? opts.merge(report: report) : opts
    end

    # The report exists to describe a failure, so it has to be on disk by
    # the time the gates raise. Ordering the two calls the other way round
    # leaves the caller nothing to read on exactly the runs it needs one.
    it 'still leaves the report on disk' do
      expect { described_class.new(run_options, ['ru']).run }
        .to raise_error(Thor::Error, /ru: No YAML files found/)

      report = JSON.parse(File.read(path))
      expect(report['gates_passed']).to be false
      expect(report['sources'].first['gate_failures'])
        .to eq(['ru: No YAML files found'])
    end

    it 'writes no report at all without the flag' do
      expect { described_class.new(run_options(report: nil), ['ru']).run }
        .to raise_error(Thor::Error, /ru: No YAML files found/)

      expect(File.exist?(path)).to be false
    end

    # An unwritable report must not become the run's diagnosis: the gate
    # message is what the operator needs, and losing it to an Errno is
    # exactly the failure the report was added to prevent.
    it 'keeps the gate failure when the report cannot be written' do
      blocked = File.join(dir, 'blocked')
      File.write(blocked, 'not a directory')

      expect do
        described_class.new(run_options(report: File.join(blocked, 'r.json')),
                            ['ru']).run
      end.to raise_error(Thor::Error, /ru: No YAML files found/)
    end

    # With the gates satisfied there is nothing better to report, so the
    # write failure is the run's outcome rather than a silent success.
    it 'fails the run when only the report could not be written' do
      blocked = File.join(dir, 'blocked2')
      File.write(blocked, 'not a directory')
      opts = { sources_dir: File.join(dir, 'sources'),
               output_dir: File.join(dir, 'out'),
               allow_empty: 'ru',
               report: File.join(blocked, 'r.json') }
      FileUtils.mkdir_p(File.join(dir, 'sources', 'data-ru', 'processed'))

      expect { described_class.new(opts, ['ru']).run }
        .to raise_error(Thor::Error, /Could not write report/)
    end
  end
end
