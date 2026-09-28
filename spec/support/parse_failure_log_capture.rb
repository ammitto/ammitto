# frozen_string_literal: true

require 'logger'
require 'stringio'

# Parse failure specs assert on the WARN line a report writes and on the
# per-run count. The configuration is reset afterwards as well as before
# because ParseFailureVisibility.mode reads Ammitto.configuration directly,
# so a mode an example sets (including an invalid one) would otherwise
# leak into every later spec that reports through a source parser.
RSpec.shared_context 'with parse failure log capture' do
  let(:io) { StringIO.new }

  before do
    Ammitto.reset_configuration!
    Ammitto::Logger.logger = Logger.new(io)
  end

  after do
    Ammitto::Logger.logger = nil
    ENV.delete('AMMITTO_PARSE_FAILURE_MODE')
    Ammitto.reset_configuration!
  end
end
