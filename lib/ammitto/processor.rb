require_relative 'sanction_item_collection'
require 'rbconfig'
require 'fileutils'

module Ammitto
  class Processor

    SOURCE_DIRECTORY = "#{Dir.home}/.ammitto/sources"
    DATA_SOURCES =  Dir.entries(SOURCE_DIRECTORY).select {|entry| File.directory? File.join(SOURCE_DIRECTORY,entry) and !(entry =='.' || entry == '..') } rescue []

    def self.prepare(date = nil)
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

    def self.fetch(term, opts)
      warn "[amitto] searching for: \"#{term}\" ..."
      results = []
      Processor::DATA_SOURCES.each do |ds|
        warn "[amitto] searching in #{ds}"
        matched = []
        Dir["#{Processor::SOURCE_DIRECTORY}/#{ds}/processed/*.yaml"].each do |source_entity|
          data = YAML::safe_load(File.read(source_entity))
          matched << data if search_matched?(data, term, opts)
        end
        results << matched
        warn "[amitto] found match: #{matched.length}"
      end
      results = SanctionItemCollection.new(results.flatten)
      warn "[amitto] found total match : #{results.length}"
      results
    end

    def self.search_matched?(data, term, opts)
      matched = data["names"].join(" ").downcase.index(term.downcase)
      unless opts.empty?
        opts = traverse_and_downcase(opts)
        matched = matched && data["entity_type"]&.downcase&.index(opts[:entity_type]) unless opts[:entity_type].nil?
        matched = matched && data["source"]&.downcase&.index(opts[:source]) unless opts[:source].nil?
        matched = matched && data["ref_number"].to_s.downcase&.index(opts[:ref_number]) unless opts[:ref_number].nil?
        matched = matched && data["ref_type"]&.downcase&.index(opts[:ref_type]) unless opts[:ref_type].nil?
        matched = matched && data["country"]&.downcase&.index(opts[:country]) unless opts[:country].nil?
        matched = matched && data["remark"]&.downcase&.index(opts[:remark]) unless opts[:remark].nil?
        matched = matched && data["designation"]&.downcase&.index(opts[:designation]) unless opts[:designation].nil?
        matched = check_documents(data, opts, matched) unless opts[:documents].nil?
        matched = check_address(data, opts, matched)  unless opts[:addresses].nil?
      end
      matched
    end

    def self.check_documents(data, opts, matched)
      return false if data["document"].nil?
      matched = matched && data["document"].map{|add| add["type"]}.join(" ")&.downcase&.index(opts[:documents][:type]) unless opts[:documents][:type].nil?
      matched = matched && data["document"].map{|add| add["number"]}.join(" ")&.downcase&.index(opts[:documents][:number]) unless opts[:documents][:number].nil?
      matched = matched && data["document"].map{|add| add["country"]}.join(" ")&.downcase&.index(opts[:documents][:country]) unless opts[:documents][:country].nil?
      matched = matched && data["document"].map{|add| add["note"]}.join(" ")&.downcase&.index(opts[:documents][:note]) unless opts[:documents][:note].nil?
      matched
    end

    def self.check_address(data, opts, matched)
      return false if data["address"].nil?
      matched = matched && data["address"].map{|add| add["street"]}.join(" ")&.downcase&.index(opts[:addresses][:street]) unless opts[:addresses][:street].nil?
      matched = matched && data["address"].map{|add| add["city"]}.join(" ")&.downcase&.index(opts[:addresses][:city]) unless opts[:addresses][:city].nil?
      matched = matched && data["address"].map{|add| add["country"]}.join(" ")&.downcase&.index(opts[:addresses][:country]) unless opts[:addresses][:country].nil?
      matched = matched && data["address"].map{|add| add["state"]}.join(" ")&.downcase&.index(opts[:addresses][:state]) unless opts[:addresses][:state].nil?
      matched = matched && data["address"].map{|add| add["zip"]}.join(" ")&.downcase&.index(opts[:addresses][:zip]) unless opts[:addresses][:zip].nil?
      matched
    end

    def self.traverse_and_downcase(hash)
      hash.each do |k, v|
        traverse_and_downcase(v) if v.is_a? Hash
        hash[k] = v.downcase if v.is_a?(String)
      end
    end

    def self.git_installed?
      void = RbConfig::CONFIG['host_os'] =~ /msdos|mswin|djgpp|mingw/ ? 'NUL' : '/dev/null'
      system "git --version >>#{void} 2>&1"
    end

  end
end
