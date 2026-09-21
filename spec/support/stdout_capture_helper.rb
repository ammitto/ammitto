# frozen_string_literal: true

require 'stringio'

# Shared by any spec that needs to assert on what a command printed.
#
# Lives here rather than inside a `describe`, the same reasoning as
# IsolatedLoadHelper: `spec_helper` already globs `spec/support/**/*.rb`,
# so a second spec file that needs this doesn't re-implement it.
module StdoutCaptureHelper
  # @yield the block whose stdout is captured
  # @return [String] everything written to $stdout during the block
  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
