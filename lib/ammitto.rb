# frozen_string_literal: true

require_relative "ammitto/version"
require 'net/http'
require 'yaml'
require 'ostruct'
require 'nokogiri'

module Ammitto
  DATA_SOURCE_ENDPOINT = "https://raw.githubusercontent.com/ammitto/data/master/processed/".freeze
  DATA_PROCESSED_ENDPOINT = "https://github.com/ammitto/data/tree/master/processed/".freeze

  class Error < StandardError; end

  class RequestError < StandardError; end

  class << self
    def search(term)
      warn "[amitto] fetching for: \"#{term}\" ..."

      response = Net::HTTP.get_response URI(DATA_PROCESSED_ENDPOINT)
      doc = Nokogiri::HTML(response.body)
      data_sources = doc.xpath('//a[contains(text(), "sanctions_list.yaml")]').map(&:text)
      results = []
      data_sources.each do |ds|
        warn "[amitto] searching in #{ds.sub('.yaml', '').gsub("_", " ")}"
        resp = Net::HTTP.get_response URI("#{DATA_SOURCE_ENDPOINT}#{ds}")
        data = YAML::safe_load(resp.body)
        res = data.find_all { |d| d["names"].join(" ").downcase.index(term.downcase) }
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