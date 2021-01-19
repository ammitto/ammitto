# frozen_string_literal: true

require_relative "ammitto/version"
require 'open-uri'
require 'yaml'
require 'ostruct'
require 'nokogiri'

module Ammitto
  DATA_SOURCE_ENDPOINT = "https://raw.githubusercontent.com/ammitto/data/master/processed/".freeze
  DATA_PROCESSED_ENDPOINT = "https://github.com/ammitto/data/tree/master/processed/".freeze

   class Error < StandardError; end

   class RequestError < StandardError; end

   class << self
     def search(text)
       warn "[amitto] fetching for: \"#{text}\" ..."

       doc = Nokogiri::HTML(URI.open(DATA_PROCESSED_ENDPOINT))
       data_sources = doc.xpath('//a[contains(text(), "sanctions_list.yaml")]').map(&:text)

       results = []
       data_sources.each do |ds|
         warn "[amitto] searching in #{ds.sub('.yaml','').gsub("_"," ")}"
         yaml_content = URI.open("#{DATA_SOURCE_ENDPOINT}#{ds}") { |f| f.read }
         yaml_data = YAML::safe_load(yaml_content)
         res = yaml_data.find_all { |data| data["names"].join(" ").downcase.index(text.downcase) }
         warn "[amitto] found match: #{res.length}"
         results << res
       end
       results = results.flatten.map { |r| OpenStruct.new(r) }
       warn "[amitto] found total match : #{results.length}"
       results
     rescue SocketError, Errno::EINVAL, Errno::ECONNRESET, EOFError,
       Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
       Net::ProtocolError, Net::ReadTimeout,
       Errno::ETIMEDOUT => e
       raise Ammitto::RequestError, "Could not access data source due to : #{e.message}"
     end
   end

end