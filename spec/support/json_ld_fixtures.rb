# frozen_string_literal: true

require 'json'

# Helpers for building JSON-LD documents on disk in specs.
#
# Lives here rather than inside a `describe` block because a method defined
# in an example group is reachable only from that group, so the next spec
# that needs the same fixture copies it. `spec_helper` already globs
# `spec/support/**/*.rb`; this is the home that glob was written for.
module JsonLdFixtures
  # Write a JSON-LD document whose @graph holds nodes with the given ids.
  #
  # @param path [String] file to write
  # @param ids [Array<String>] @id values, one node each
  # @return [void]
  def write_graph(path, ids)
    File.write(path, JSON.generate('@graph' => ids.map { |i| { '@id' => i } }))
  end
end
