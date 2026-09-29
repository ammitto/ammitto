# frozen_string_literal: true

require 'ammitto'
require 'open3'
require 'rbconfig'

# Ruby's top-level handler and loggers call full_message with keywords such
# as highlight:, so the overrides must accept and forward them.
RSpec.describe Ammitto::Error do
  it 'accepts the keywords Exception#full_message takes' do
    error = described_class.new('boom', context: 'ctx')

    expect(error.full_message(highlight: false, order: :top)).to include('boom', '(Context: ctx)')
  end

  it 'keeps the zero-argument output' do
    error = begin
      raise described_class.new('boom', context: 'ctx')
    rescue described_class => e
      e
    end

    plain = Exception.instance_method(:full_message).bind_call(error)

    expect(error.full_message).to eq("#{plain} (Context: ctx)")
  end

  it 'forwards keywords through NetworkError' do
    error = Ammitto::NetworkError.new('down', url: 'https://x.test', status_code: 503)

    expect(error.full_message(highlight: false)).to include('down', 'URL: https://x.test', 'Status: 503')
  end

  # Callers rescue Ammitto::Error to catch everything the gem raises, so an
  # error class outside the hierarchy escapes them.
  describe 'coverage of the gem\'s own error classes' do
    # The CLI loads its commands lazily, so every file under lib/ammitto is
    # required, in a child process to keep that load out of the other specs.
    scan = <<~RUBY
      require 'ammitto'
      Dir[File.join(ARGV[0], 'ammitto/**/*.rb')].each { |f| require f }
      gem_errors = ObjectSpace.each_object(Class).select do |klass|
        klass < Exception && klass.name&.start_with?('Ammitto::')
      end
      gem_errors.each do |klass|
        caught = begin
          raise klass.allocate
        rescue Ammitto::Error
          true
        rescue Exception
          false
        end
        puts "\#{caught ? 'caught' : 'escaped'} \#{klass.name}"
      end
    RUBY

    let(:report) do
      lib = File.expand_path('../../lib', __dir__)
      out, status = Open3.capture2(RbConfig.ruby, '-I', lib, '-e', scan, lib)
      raise "scan failed: #{status}" unless status.success?

      out.lines.map(&:split)
    end

    it 'finds the gem\'s error classes to check' do
      expect(report.map(&:last)).to include('Ammitto::Validation::UnknownCountryError',
                                            'Ammitto::Utils::IriSanitizer::MissingLocalIdError',
                                            'Ammitto::Cmd::Harmonize::SourceTransforms::AnnouncementFormatError')
    end

    it 'rescues every one of them with Ammitto::Error' do
      expect(report.filter_map { |verdict, name| name if verdict == 'escaped' }).to eq([])
    end
  end

  it 'lets a moved error keep a bare raise' do
    expect { raise Ammitto::Data::China::SchemaNotFoundError }
      .to raise_error(Ammitto::Data::China::SchemaNotFoundError)
  end

  it 'keeps UnknownCountryError an ArgumentError for existing rescuers' do
    rescued = begin
      raise Ammitto::Validation::UnknownCountryError, 'xx'
    rescue described_class => e
      e
    end

    expect(rescued).to be_a(ArgumentError)
  end

  it 'leaves subclass matching to ordinary ancestry' do
    expect do
      raise Ammitto::Validation::UnknownCountryError, 'xx'
    rescue Ammitto::NetworkError
      nil
    end.to raise_error(Ammitto::Validation::UnknownCountryError)
  end
end
