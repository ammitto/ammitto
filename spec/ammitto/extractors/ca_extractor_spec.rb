# frozen_string_literal: true

require 'ammitto'
require 'ammitto/extractors/ca_extractor'

# `ammitto fetch ca --format jsonld` used to die with
# `undefined method 'xpath' for an instance of String`.
#
# Two things were wrong and neither was visible from the extractor's own
# documentation: `fetch` returns the response body, not the
# `Nokogiri::XML::Document` its YARD claimed, and the extract methods
# looked for `//INDIVIDUAL` and `//ENTITY` in a document that is a
# `<data-set>` of `<record>` elements and always has been. Canada is read
# through `Sources::Ca::SanctionsList` on the `--format yaml` path, which
# is what the data-ca workflow runs; nothing has ever read it here.
RSpec.describe Ammitto::Extractors::CaExtractor do
  subject(:extractor) { described_class.new }

  describe '#extract_entities' do
    it 'refuses instead of reporting an empty list' do
      error = begin
        extractor.extract_entities('<data-set><record/></data-set>')
        nil
      rescue Ammitto::Error => e
        e
      end

      expect(error.class).to eq(Ammitto::ParseError)
      expect(error.message).to match(/cannot parse sema-lmes\.xml/)
      expect(error.message).to match(/Sources::Ca::SanctionsList/)
    end
  end

  describe '#extract_entries' do
    it 'refuses on the same terms' do
      error = begin
        extractor.extract_entries('<data-set><record/></data-set>')
        nil
      rescue Ammitto::Error => e
        e
      end

      expect(error.class).to eq(Ammitto::ParseError)
      expect(error.message).to match(/cannot parse sema-lmes\.xml/)
    end
  end

  describe '#run' do
    # BaseExtractor#run rescues StandardError into `status: :error`, and
    # FetchCommand#enforce_exit_status raises on that, so the refusal
    # reaches the shell as a nonzero exit rather than "1 succeeded".
    it 'reports an error rather than zero entities' do
      # Stubbing the subject's own `fetch` is the only way to reach `run`
      # without a network call. `fetch` is not what this example is
      # about — the refusal that follows it is.
      # rubocop:disable RSpec/SubjectStub
      allow(extractor).to receive(:fetch).and_return('<data-set/>')
      # rubocop:enable RSpec/SubjectStub

      result = extractor.run

      expect(result[:status]).to eq(:error)
      expect(result[:error]).to match(/cannot parse sema-lmes\.xml/)
      expect(result).not_to have_key(:entities)
    end
  end
end
