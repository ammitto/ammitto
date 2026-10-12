# frozen_string_literal: true

require 'tmpdir'
require 'ammitto'
require 'ammitto/cli'
require 'ammitto/cli/validate_command'

# `ammitto validate china --verbose` printed "Run with --verbose to see
# detailed errors": the top-level CLI declares `--verbose`/`-v` as a class
# option, so Thor took the flag before `validate` forwarded its arguments.
RSpec.describe 'ammitto validate china --verbose' do
  def run_cli(*argv)
    Ammitto::CLI.start(argv)
  rescue SystemExit => e
    e.status
  end

  around do |example|
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'broken.yml'), "id: x\n")
      @dir = dir
      example.run
    end
  end

  %w[--verbose -v].each do |flag|
    it "prints each file's errors with #{flag}" do
      expect { run_cli('validate', 'china', @dir, flag) }
        .to output(/=== Errors ===\n\n.*broken\.yml:\n  - /).to_stdout
    end
  end

  it 'prints the errors when AMMITTO_VERBOSE is set' do
    stub_const('ENV', ENV.to_h.merge('AMMITTO_VERBOSE' => 'true'))
    expect { run_cli('validate', 'china', @dir) }
      .to output(/=== Errors ===/).to_stdout
  end

  it 'leaves list working when the flag is forwarded to it' do
    expect { run_cli('validate', 'list', @dir, '--verbose') }
      .to output(/broken\.yml \(announcement\)/).to_stdout
  end

  it 'points at --verbose without the flag' do
    stub_const('ENV', ENV.to_h.except('AMMITTO_VERBOSE'))
    expect { run_cli('validate', 'china', @dir) }
      .to output(/Run with --verbose to see detailed errors/).to_stdout
  end
end
