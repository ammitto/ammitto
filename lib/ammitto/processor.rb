require_relative 'sanction_item_collection'
require 'rbconfig'
require 'fileutils'

module Ammitto
  class Processor

    DATA_SOURCES = ['un-data','us-govt-data','eu-data','wb-data'].freeze
    SOURCE_DIRECTORY = "#{Dir.home}/.ammitto/sources"

    def self.prepare(date=nil)
      last_updated = Time.parse(File.open("#{SOURCE_DIRECTORY}/update.log", &:gets)) rescue nil
      if date.nil? || last_updated.nil? || date && last_updated && ((date - last_updated) / 3600) > 24
        raise "[amitto] Please install git in your system!" if !git_installed?
        FileUtils.mkdir_p SOURCE_DIRECTORY
        DATA_SOURCES.each do |ds|
          FileUtils.rm_rf "#{SOURCE_DIRECTORY}/#{ds}" if File.directory?("#{SOURCE_DIRECTORY}/#{ds}")
          `git clone git@github.com:ammitto/#{ds}.git #{SOURCE_DIRECTORY}/#{ds}`
          warn "[amitto] Done fetching data sources for #{ds}!"
        end
        open("#{SOURCE_DIRECTORY}/update.log", "w") { |file| file.write(Time.now.to_s) }
        warn "[amitto] Updated data sources \"#{DATA_SOURCES.join(", ")}\" !"
      end
      true
    end

    def self.fetch(term,**opts)
      warn "[amitto] searching for: \"#{term}\" ..."
      results = []
      Processor::DATA_SOURCES.each do |ds|
        warn "[amitto] searching in #{ds}"
        matched = []
        opts.each { |k, v| v.downcase! if v.is_a?(String) }
        Dir["#{Processor::SOURCE_DIRECTORY}/#{ds}/processed/*.yaml"].each do |source_entity|
          data = YAML::safe_load(File.read(source_entity))
          conditions = data["names"].join(" ").downcase.index(term.downcase)
          conditions = conditions && data["entity_type"]&.downcase&.index(opts[:entity_type]) unless opts[:entity_type].nil?
          conditions = conditions && data["source"]&.downcase&.index(opts[:source]) unless opts[:source].nil?
          conditions = conditions && data["ref_number"]&.downcase&.index(opts[:ref_number]) unless opts[:ref_number].nil?
          conditions = conditions && data["ref_type"]&.downcase&.index(opts[:ref_type]) unless opts[:ref_type].nil?
          conditions = conditions && data["country"]&.downcase&.index(opts[:country]) unless opts[:country].nil?
          conditions = conditions && data["remark"]&.downcase&.index(opts[:remark]) unless opts[:remark].nil?
          conditions = conditions && data["designation"]&.downcase&.index(opts[:designation]) unless opts[:designation].nil?
          matched << data if conditions
        end
        results << matched
        warn "[amitto] found match: #{matched.length}"
      end
      results = SanctionItemCollection.new(results.flatten)
      warn "[amitto] found total match : #{results.length}"
      results
    end

    def self.git_installed?
      void = RbConfig::CONFIG['host_os'] =~ /msdos|mswin|djgpp|mingw/ ? 'NUL' : '/dev/null'
      system "git --version >>#{void} 2>&1"
    end

  end
end
