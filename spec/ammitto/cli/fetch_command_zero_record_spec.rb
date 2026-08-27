# frozen_string_literal: true

require 'ammitto'
require 'ammitto/cli'
require 'ammitto/cli/fetch_command'
require 'ammitto/extractors/base_extractor'

# A harvest that wrote nothing is a failure, not a quiet success.
#
# `fetch_source` recorded the written count and never consulted it, while
# `enforce_exit_status` selects on `:error` only. So a source whose document
# parsed to nothing — a changed XML namespace, a maintenance page served with a
# 200, a renamed root element — produced "1 succeeded, 0 failed" and exit 0.
# Nothing removes the previous harvest's files, so the downstream harmonize
# gate then passed on yesterday's data and stayed green as well.
RSpec.describe Ammitto::Cmd::FetchCommand do
  subject(:command) { described_class.new({}, ['uk']) }

  describe 'a source that parsed to nothing' do
    it 'reports an error rather than a success' do
      # Drive the real fetch_source, with only the transport and the writer
      # stubbed, so the count branch itself is what is under test.
      extractor = instance_double(
        Ammitto::Extractors::BaseExtractor,
        fetch: '<xml/>', api_endpoint: 'https://example.test/x'
      )
      allow(extractor).to receive(:respond_to?).and_return(false)
      klass = class_double(Ammitto::Extractors::BaseExtractor, new: extractor)
      model = Class.new do
        def self.from_xml(_content) = new
        def self.name = 'FakeModel'
      end

      # Stubbing the subject's own collaborators is the only way to reach
      # the count branch without a network call and a real parser. The
      # branch itself — count.zero? — is not stubbed, which is what this
      # example is for.
      # rubocop:disable RSpec/SubjectStub
      allow(command).to receive_messages(
        extractor_class_for: klass,
        source_model_class_for: model,
        save_as_yaml: 0
      )

      # rubocop:enable RSpec/SubjectStub

      result = command.send(:fetch_source, :uk)

      expect(result[:status]).to eq(:error)
      expect(result[:error]).to match(/wrote 0 records/)
    end
  end

  # `--format jsonld` is documented, and it takes a different branch that
  # calls the extractor's own #run. That branch reported :success with
  # zero entities, so the refusal had to cover it too or the lie stayed
  # reachable through a supported flag.
  describe 'the non-yaml path, which bypassed the guard' do
    it 'refuses an extraction that produced nothing' do
      result = command.send(
        :refuse_empty_extraction, :uk,
        { code: :uk, entities: 0, entries: 0, status: :success }
      )

      expect(result[:status]).to eq(:error)
      expect(result[:error]).to match(/extracted 0 records/)
    end

    it 'leaves a run that produced records alone' do
      run = { code: :uk, entities: 12, entries: 12, status: :success }

      expect(command.send(:refuse_empty_extraction, :uk, run)).to eq(run)
    end

    it 'does not second-guess a run that already failed' do
      run = { code: :uk, status: :error, error: 'network' }

      expect(command.send(:refuse_empty_extraction, :uk, run)).to eq(run)
    end
  end

  # The three examples above prove the predicate. They do not prove the
  # guard is wired into the routing, which is the part that regressed
  # before: the yaml branch was guarded and the other branch was not.
  describe 'the routing itself' do
    [
      ['jsonld', 'a documented non-yaml format'],
      ['yaml',   'yaml with no source model, which also falls through']
    ].each do |format, description|
      it "refuses a zero-record run via #{description}" do
        extractor = instance_double(
          Ammitto::Extractors::BaseExtractor,
          run: { code: :uk, entities: 0, entries: 0, status: :success }
        )
        allow(extractor).to receive(:verbose=)
        klass = class_double(Ammitto::Extractors::BaseExtractor, new: extractor)

        cmd = described_class.new({ 'format' => format }, ['uk'])
        allow(cmd).to receive_messages(
          extractor_class_for: klass,
          source_model_class_for: nil,
          cache_dir: Dir.mktmpdir
        )

        result = cmd.send(:fetch_source, :uk)

        expect(result[:status]).to eq(:error)
        expect(result[:error]).to match(/extracted 0 records/)
      end
    end
  end

  describe 'enforce_exit_status' do
    it 'raises for a zero-record result, because it is now an error' do
      results = [{ code: :uk, status: :error, error: 'wrote 0 records' }]

      expect { command.send(:enforce_exit_status, results) }
        .to raise_error(Thor::Error, /uk/)
    end

    it 'stays quiet when every source wrote something' do
      results = [{ code: :uk, status: :success, count: 3 }]

      expect { command.send(:enforce_exit_status, results) }.not_to raise_error
    end
  end
end
