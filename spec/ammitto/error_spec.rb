# frozen_string_literal: true

require 'ammitto'

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
end
