require_relative 'sanction_item_collection'
require 'rbconfig'

module Ammitto
  class Processor

    DATA_SOURCES = ['un-data','us-govt-data','eu-data','wb-data'].freeze
    SOURCE_DIRECTORY = "#{Dir.home}/.ammitto/sources"

    def self.prepare(date=nil)
      raise "kolaa"
      last_updated = Time.parse(File.open("#{SOURCE_DIRECTORY}/update.log", &:gets)) rescue nil
      if date.nil? || date && last_updated && ((date - last_updated) / 3600) > 24
        warn "[amitto] Please install git in your system!" and return if !git_installed
        FileUtils.mkdir_p SOURCE_DIRECTORY
        DATA_SOURCES.each do |ds|
          FileUtils.rm_rf "#{SOURCE_DIRECTORY}/#{ds}" if File.directory?("#{SOURCE_DIRECTORY}/#{ds}")
          `git clone git@github.com:ammitto/#{ds}.git #{SOURCE_DIRECTORY}/#{ds}`
          warn "[amitto] Done fetching data sources for #{ds}!"
        end
        open("#{SOURCE_DIRECTORY}/update.log", "w") { |file| file.write(Time.now.to_s) }
      end
      warn "[amitto] Updated data sources \"#{DATA_SOURCES.join(", ")}\" !"
    end

    def self.fetch(term)
      warn "[amitto] searching for: \"#{term}\" ..."
      results = []
      Processor::DATA_SOURCES.each do |ds|
        warn "[amitto] searching in #{ds}"
        matched = []
        Dir["#{Processor::SOURCE_DIRECTORY}/#{ds}/processed/*.yaml"].each do |source_entity|
          data = YAML::safe_load(File.read(source_entity))
          matched << data if data["names"].join(" ").downcase.index(term.downcase)
        end
        results << matched
        warn "[amitto] found match: #{matched.length}"
      end
      results = SanctionItemCollection.new(results.flatten)
      warn "[amitto] found total match : #{results.length}"
      results
    end

    def self.git_installed
      void = RbConfig::CONFIG['host_os'] =~ /msdos|mswin|djgpp|mingw/ ? 'NUL' : '/dev/null'
      system "git --version >>#{void} 2>&1"
    end

  end
end
