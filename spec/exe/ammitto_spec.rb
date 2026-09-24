# frozen_string_literal: true

require 'open3'

# The executable has to run as a real subprocess: under RSpec $stdout is
# whatever the runner set up, so only a child process writing to a pipe
# reproduces the block buffering a CI log sees.
RSpec.describe 'exe/ammitto' do
  let(:exe) { File.expand_path('../../exe/ammitto', __dir__) }

  it 'writes a failed fetch in execution order when stdout and stderr share a pipe' do
    # cn has no fetch path, so this fails without touching the network.
    output, status = Open3.capture2e(RbConfig.ruby, exe, 'fetch', 'cn')

    expect(status).not_to be_success
    summary = output.index('Fetch complete:')
    failure = output.index('Fetch failed for: cn')
    expect(summary).not_to be_nil, output
    expect(failure).not_to be_nil, output
    expect(summary).to be < failure, output
  end
end
