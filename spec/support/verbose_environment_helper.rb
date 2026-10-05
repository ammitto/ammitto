# frozen_string_literal: true

# Runs a block with the verbose environment variables set to known values
# and the configuration rebuilt from them.
#
# Configuration reads the environment once, when it is built, so setting a
# variable inside an example has no effect until the memoized configuration
# is rebuilt. The environment and the configuration object that was in
# place are both put back afterwards, so a verbose run cannot leak into the
# next example and a configuration the suite had already set up survives.
# Lives here because more than one spec file needs it (C8).
module VerboseEnvironmentHelper
  # @param values [Hash{String => String, nil}] variable name => value;
  #   a nil value leaves the variable unset
  # @yield the block run under that environment
  def with_verbose_env(values = {})
    previous = Ammitto.instance_variable_get(:@configuration)
    saved = verbose_env_names.to_h { |name| [name, ENV.fetch(name, nil)] }
    verbose_env_names.each { |name| ENV.delete(name) }
    values.each { |name, value| ENV[name] = value unless value.nil? }
    Ammitto.reset_configuration!
    yield
  ensure
    saved.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    Ammitto.instance_variable_set(:@configuration, previous)
  end

  private

  # Resolved at call time: spec/support loads before the library does.
  def verbose_env_names
    provider = Ammitto::Config::EnvProvider
    ["#{provider::PREFIX}#{provider::ENV_MAPPING.fetch(:verbose)}", provider::LEGACY_VERBOSE]
  end
end
