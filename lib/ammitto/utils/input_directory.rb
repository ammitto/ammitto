# frozen_string_literal: true

require_relative '../error'

module Ammitto
  module Utils
    # Glob and existence predicates can hide denied inspection as absence.
    # Cleanup needs verified discovery rather than an apparently empty tree.
    module InputDirectory
      module_function

      def directory?(path)
        File.stat(path).directory?
      rescue Errno::ENOENT
        false
      end

      def verify_tree!(directory)
        pending = [directory]
        visited = {}
        until pending.empty?
          path = pending.pop
          physical = File.realpath(path)
          next if visited[physical]

          visited[physical] = true
          accessible = File.readable?(path) && File.executable?(path)
          raise Ammitto::Error, "Cannot inspect input directory #{path}: read and search access required" unless accessible

          Dir.children(path).each do |child|
            child_path = File.join(path, child)
            pending << child_path if File.stat(child_path).directory?
          end
        end
      end
    end
  end
end
