# frozen_string_literal: true

require 'spec_helper'

# Each file that asks Ammitto.configuration whether verbose is on must load
# the configuration itself. RSpec has already required the whole tree, so
# only a fresh subprocess shows a standalone require path that forgot to.
RSpec.describe 'Verbose check loaded from a standalone require' do
  include IsolatedLoadHelper

  entry_points = {
    'ammitto/data/japan/meti' => 'Ammitto::Data::Japan::Meti::Extractor.new.send(:verbose?)',
    'ammitto/data/japan/meti/extractor' => 'Ammitto::Data::Japan::Meti::Extractor.new.send(:verbose?)',
    'ammitto/extractors/base_extractor' => 'Ammitto::Extractors::BaseExtractor.allocate.send(:verbose?)',
    'ammitto/extractors/ru_extractor' => 'Ammitto::Extractors::RuExtractor.allocate.send(:verbose?)',
    'ammitto/scrapers/base_page' => 'Ammitto::Scrapers::BasePage.new.send(:verbose?)',
    'ammitto/scrapers/cn/cn_sanctions_scraper' => 'Ammitto::Scrapers::Cn::CnSanctionsScraper.new.send(:verbose?)',
    'ammitto/scrapers/ru/ru_sanctions_scraper' => 'Ammitto::Scrapers::Ru::RuSanctionsScraper.new.send(:verbose?)',
    'ammitto/serialization/json_ld_graph_exporter' => 'Ammitto.configuration.verbose'
  }

  entry_points.each do |path, check|
    it "answers the verbose check after requiring #{path} alone" do
      ok, stderr = load_in_subprocess(path, check)

      expect(ok).to be(true), stderr
    end
  end
end
