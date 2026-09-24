# frozen_string_literal: true

require 'stringio'
require 'tmpdir'
require 'fileutils'
require 'ammitto'
require 'ammitto/cli'
require 'ammitto/cli/fetch_command'
# Extractors are loaded lazily by the fetch command, not by `ammitto`;
# the disposal examples below verify a double against the real class.
require 'ammitto/extractors/tr_extractor'

RSpec.describe Ammitto::Cmd::FetchCommand do
  describe 'exit honesty' do
    it 'raises Thor::Error when a requested source fails' do
      cmd = described_class.new({}, ['cn'])

      expect { cmd.run }
        .to raise_error(Thor::Error, /Fetch failed for: cn/)
        .and output(/0 succeeded, 1 failed/).to_stdout
    end

    it 'fails an explicit jp fetch loudly' do
      cmd = described_class.new({}, ['jp'])

      expect { cmd.run }
        .to raise_error(Thor::Error, /Fetch failed for: jp/)
        .and output(/0 succeeded, 1 failed/).to_stdout
    end

    it 'fails the run when only some sources fail' do
      cmd = described_class.new({}, %w[uk cn])
      allow(cmd).to receive(:fetch_source).and_call_original
      allow(cmd).to receive(:fetch_source)
        .with(:uk).and_return({ code: :uk, status: :success, count: 3 })

      expect { cmd.run }
        .to raise_error(Thor::Error, /Fetch failed for: cn/)
        .and output(/1 succeeded, 1 failed/).to_stdout
    end

    it 'names every failed source in the error' do
      cmd = described_class.new({}, %w[uk eu])
      allow(cmd).to receive(:fetch_source) do |source|
        { code: source, status: :error, error: 'boom' }
      end

      expect { cmd.run }
        .to raise_error(Thor::Error, /Fetch failed for: uk, eu/)
        .and output(/0 succeeded, 2 failed/).to_stdout
    end

    it 'does not raise when all requested sources succeed' do
      cmd = described_class.new({}, %w[uk])
      allow(cmd).to receive(:fetch_source)
        .with(:uk).and_return({ code: :uk, status: :success, count: 3 })

      expect { cmd.run }
        .to output(/1 succeeded, 0 failed/).to_stdout
    end
  end

  describe 'disposing of the downloaded workbook' do
    let(:extractor) { instance_double(Ammitto::Extractors::TrExtractor) }
    let(:model_class) { class_double(Ammitto::Sources::Tr::SanctionsList) }

    def parse
      described_class.new({}, ['tr'])
                     .send(:parse_xlsx, model_class, 'book.xlsx', extractor)
    end

    it 'disposes of it after a parse that succeeds' do
      allow(model_class).to receive(:from_xlsx).and_return(:parsed)
      allow(extractor).to receive(:cleanup)

      expect(parse).to eq(:parsed)
      expect(extractor).to have_received(:cleanup)
    end

    it 'disposes of it after a parse that refuses the payload' do
      # A refused harvest used to keep its workbook: cleanup ran only on
      # the returning path.
      allow(model_class).to receive(:from_xlsx)
        .and_raise(Ammitto::Sources::Tr::IntegrityError, 'refused')
      allow(extractor).to receive(:cleanup)

      expect { parse }
        .to raise_error(Ammitto::Sources::Tr::IntegrityError, 'refused')
      expect(extractor).to have_received(:cleanup)
    end

    it 'keeps the refusal visible when disposal also fails' do
      # The operator needs to know why the harvest was refused, not that
      # a temp file resisted deletion.
      allow(model_class).to receive(:from_xlsx)
        .and_raise(Ammitto::Sources::Tr::IntegrityError, 'refused')
      allow(extractor).to receive(:cleanup).and_raise(IOError, 'busy')

      expect do
        expect { parse }
          .to raise_error(Ammitto::Sources::Tr::IntegrityError, 'refused')
      end.to output(/\[cleanup\] busy/).to_stderr
    end

    it 'reports a disposal failure when there is no refusal to hide' do
      allow(model_class).to receive(:from_xlsx).and_return(:parsed)
      allow(extractor).to receive(:cleanup).and_raise(IOError, 'busy')

      expect { parse }.to raise_error(IOError, 'busy')
    end

    it 'disposes of it when the operator cancels the parse' do
      # Interrupt is not a StandardError, so Ctrl-C during a long parse
      # took an exit that ran no cleanup and leaked the workbook.
      allow(model_class).to receive(:from_xlsx).and_raise(Interrupt)
      allow(extractor).to receive(:cleanup)

      expect { parse }.to raise_error(Interrupt)
      expect(extractor).to have_received(:cleanup)
    end

    it 'keeps the cancellation visible when disposal also fails' do
      allow(model_class).to receive(:from_xlsx).and_raise(Interrupt)
      allow(extractor).to receive(:cleanup).and_raise(IOError, 'busy')

      expect do
        expect { parse }.to raise_error(Interrupt)
      end.to output(/\[cleanup\] busy/).to_stderr
    end
  end
end
