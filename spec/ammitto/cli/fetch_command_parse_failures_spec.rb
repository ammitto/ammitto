# frozen_string_literal: true

require 'ammitto'
require 'ammitto/cli'
require 'ammitto/cli/fetch_command'
require 'ammitto/extractors/base_extractor'

module FetchCommandParseFailuresSpecHelpers
  # Stands in for a source model whose xlsx parser meets one unreadable date.
  class FakeModel
    def self.from_xlsx(_path)
      Ammitto::ParseFailureVisibility.report(
        source: :nz, field: :date_of_birth, value: '31/02/1970'
      )
      new
    end
  end
end

# The nz and eu_vessels xlsx parsers and the un_vessels pdf parser read dates while
# fetching, and harmonize only reloads the YAML written here, so a value
# they could not read is reported during fetch or not at all. Without a
# per-run count the fetch summary said nothing, and in silent mode the
# failure left no trace anywhere.
RSpec.describe Ammitto::Cmd::FetchCommand do
  include_context 'with parse failure log capture'

  subject(:command) { described_class.new({}, ['nz']) }

  before do
    extractor = instance_double(
      Ammitto::Extractors::BaseExtractor,
      fetch: '/tmp/nz.xlsx', api_endpoint: 'https://example.test/x'
    )
    allow(extractor).to receive(:respond_to?).and_return(false)
    # Transport and writer are stubbed so the run under test is the real
    # fetch_all, whose count and summary are what this spec is about.
    # rubocop:disable RSpec/SubjectStub
    allow(command).to receive_messages(
      extractor_class_for: class_double(Ammitto::Extractors::BaseExtractor, new: extractor),
      source_model_class_for: FetchCommandParseFailuresSpecHelpers::FakeModel,
      save_as_yaml: 1
    )
    # rubocop:enable RSpec/SubjectStub
  end

  it 'counts a fetch-time parse failure in the fetch summary' do
    Ammitto.configuration.parse_failure_mode = :silent

    expect { command.run }.to output(/Parse failures by source:\n  nz: 1\n/).to_stdout
  end
end
