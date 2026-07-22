# frozen_string_literal: true

module Ammitto
  module Cmd
    # CLI command for fetching China sanctions data
    #
    # @example
    #   ammitto source china fetch mofcom-unreliable-entity-list
    #   ammitto source china fetch mfa-anti-sanction-list
    #   ammitto source china validate
    #
    class ChinaCommand
      def initialize(options, args)
        @options = options
        @args = args
      end

      def run
        command = @args.first
        subcommand = @args[1]
        args = @args[2..]

        case command
        when 'fetch'
          fetch(subcommand, args)
        when 'validate'
          validate
        when 'list'
          list_sources
        else
          raise ArgumentError, "Unknown command: #{command}. Use 'fetch', 'validate', or 'list'"
        end
      end

      private

      def fetch(source, _args)
        require_relative '../data/china'

        raise ArgumentError, "Source required. Available: #{available_sources.join(', ')}" unless source

        raise ArgumentError, "Invalid source: #{source}. Available: #{available_sources.join(', ')}" unless Ammitto::Data::China::Extractor.valid_source?(source)

        output_dir = @options[:output] || default_output_dir(source)

        puts "Fetching #{source}..."
        extractor = Ammitto::Data::China::Extractor.new(source, verbose: @options[:verbose])
        data = extractor.fetch

        if data.empty?
          warn "No data extracted from #{source}"
          return
        end

        save_data(data, output_dir, source)
        puts "Saved #{data.size} items to #{output_dir}"
      end

      def validate
        require_relative '../data/china/validator'

        sources_dir = @options[:sources] || File.join(Dir.pwd, 'sources')
        validator = Ammitto::Data::China::Validator.new

        puts "Validating YAML files in #{sources_dir}..."
        puts '-' * 50

        report = validator.validate_all(sources_dir)

        puts "Total files: #{report[:total_files]}"
        puts "Valid files: #{report[:valid_files]}"
        puts "Invalid files: #{report[:invalid_files]}"
        puts

        if report[:invalid_files].positive?
          puts 'Errors:'
          report[:errors].each do |error|
            puts "  #{error[:file]}"
            error[:errors].each do |e|
              puts "    - #{e[:message]}"
            end
          end
          exit 1
        else
          puts 'All files are valid!'
        end
      end

      def list_sources
        puts 'Available China data sources:'
        puts '-' * 50
        Ammitto::Data::China::Extractor.available_sources.each do |source|
          puts "  * #{source}"
        end
      end

      def available_sources
        Ammitto::Data::China::Extractor.available_sources
      end

      def default_output_dir(source)
        File.join(Dir.pwd, 'sources', 'sanction-lists', source.gsub('mofcom-', '').gsub('mfa-', ''))
      end

      def save_data(data, output_dir, _source)
        require 'fileutils'
        FileUtils.mkdir_p(output_dir)

        data.each_with_index do |item, index|
          filename = generate_filename(item, index)
          filepath = File.join(output_dir, filename)
          File.write(filepath, item.to_yaml)
        end
      end

      def generate_filename(item, _index)
        date = item[:publish_date] || Date.today.to_s
        date_slug = date.to_s.gsub('-', '')

        # Generate ID from title
        id = item[:title].to_s
                         .gsub(/[^\u4e00-\u9fa5a-zA-Z0-9\s-]/, '')
                         .gsub(/\s+/, '-')
                         .gsub(/-+/, '-')
                         .downcase
                         .slice(0, 50)

        "#{date_slug}-#{id}.yml"
      end
    end
  end
end
