# frozen_string_literal: true

require_relative '../configuration'
require_relative '../logger'

module Ammitto
  module Exporter
    # Warn-once notice for the exporters that shipped in 1.0.0 and are
    # superseded by the CLI. They stay loadable so existing callers keep
    # working until 2.0, but a caller must learn the replacement without the
    # warning repeating on every instance in a loop.
    module LegacyDeprecation
      # The CLI reads data-* source YAML (`harmonize`) or the cache
      # (`export`), where these classes read `<source>-data/processed`, so
      # the notice must not promise equivalent output.
      GUIDANCE = 'use the `ammitto harmonize` or `ammitto export` command ' \
                 'instead (different inputs and outputs, not a drop-in)'

      @warned = Set.new
      @mutex = Mutex.new

      class << self
        # The pid is part of the key because a forked worker inherits the
        # parent's set and would otherwise never warn in its own stderr.
        #
        # @param klass [Class] the deprecated exporter
        # @return [void]
        def warn_once(klass)
          first = @mutex.synchronize { @warned.add?([Process.pid, klass]) }
          return unless first

          Logger.warn("#{klass.name} is deprecated and will be removed in " \
                      "2.0; #{GUIDANCE}")
        end

        private

        # Lets a spec observe the first-use warning again; specs reach it
        # with `send` so it stays off the public surface.
        def reset!
          @mutex.synchronize { @warned.clear }
        end
      end
    end
  end
end
