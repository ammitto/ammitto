# frozen_string_literal: true

require_relative "ammitto/version"
require 'net/http'
require 'yaml'
require 'nokogiri'
require 'ammitto/processor'
require 'time'

module Ammitto

  class Error < StandardError; end

  class RequestError < StandardError; end

  class << self

    def search(term)
      Processor.prepare(Time.now)
      Processor.fetch(term)
    end

    def update_data_source
      Processor.prepare
    end


  end

end