require 'time'

class Processor

  DATA_SOURCES = ['un-data','us-govt-data','eu-data','wb-data'].freeze
  SOURCE_DIRECTORY = "#{Dir.home}/.ammitto/sources"

  def self.prepare(date)
    last_updated = Time.parse(File.open("#{SOURCE_DIRECTORY}/update.log", &:gets)) rescue nil
    if date.nil? || date && last_updated && ((date - last_updated) / 3600) > 24
      FileUtils.mkdir_p SOURCE_DIRECTORY
      DATA_SOURCES.each do |ds|
        FileUtils.rm_rf "#{SOURCE_DIRECTORY}/#{ds}" if File.directory?("#{SOURCE_DIRECTORY}/#{ds}")
        `git clone git@github.com:ammitto/#{ds}.git #{SOURCE_DIRECTORY}/#{ds}`
         warn "Done fetching data sources for #{ds}!"
      end
      open("#{SOURCE_DIRECTORY}/update.log", "w") { |file| file.write(Time.now.to_s) }
    end

  end

end