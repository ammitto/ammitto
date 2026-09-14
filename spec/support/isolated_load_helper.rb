# frozen_string_literal: true

require 'tempfile'

# Shared by every source's `isolated_load_spec.rb`: each directory proves
# its model files stand up on their own by requiring them in a fresh
# subprocess, since RSpec has already required the whole tree by the time
# an example runs and an in-process require would prove nothing.
#
# Lives here rather than inside a `describe` so more than one spec can
# reach it; `spec_helper` already globs `spec/support/**/*.rb`.
module IsolatedLoadHelper
  # Returns [ok, stderr]. Keeping stderr matters: a missing require fails
  # with a NameError naming the constant, and discarding it leaves the
  # failure message as a bare "expected true, got false".
  #
  # @param path [String] the require path, relative to lib/
  # @param and_then [String, nil] extra code to run after the require, to
  #   force lazily-resolved references (see the au spec for why)
  # @return [Array(Boolean, String)] subprocess success and its stderr
  def load_in_subprocess(path, and_then = nil)
    lib = File.expand_path('../../lib', __dir__)
    script = and_then ? "require '#{path}'; #{and_then}" : "require '#{path}'"
    err = Tempfile.new('isolated_load')
    ok = system(RbConfig.ruby, '-I', lib, '-e', script,
                out: File::NULL, err: err.path)
    [ok, File.read(err.path)]
  ensure
    err&.close
    err&.unlink
  end
end
