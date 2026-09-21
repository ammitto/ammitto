# frozen_string_literal: true

require_relative '../../extractors/registry'

module Ammitto
  module Cmd
    module Fetch
      module SourceRegistry
        # Sources this command has no way to fetch, keyed to the error an
        # explicit fetch reports. This is a statement about capability, not
        # about how anyone chose to manage the data: reporting the absence
        # beats a fetch path that succeeds without writing anything.
        #
        # cn: no automated source fetch exists, here or in data-cn, whose
        #     scripts only load, merge and validate what is already there.
        # jp: announcement YAML under data-jp/sources/sanction-lists, curated
        #     with data-jp's own scripts from METI/MOFA/MOF publications (the METI
        #     End User List URL is revision-stamped and discovered from a
        #     Japanese index page). The gem's from_pdf was a placeholder that
        #     saved zero files, and harmonize prefers processed/ over the
        #     curated announcements, so partial automated output would shadow
        #     the curated data.
        # Not "unmaintained" — fetched and processed elsewhere. data-jp
        # carries its own toolchain (download_foreign_user_list.rb,
        # convert_html_to_yaml.rb, update_foreign_user_list.rb,
        # validate_yaml_structure.rb) which produces the curated YAML under
        # its sources/, and that is what harmonize reads: 5,097 published
        # entities on 2026-08-20. data-cn is NOT the same shape — it has no
        # downloader and no converter; its YAML is gathered by hand.
        #
        # What THIS command's jp path does is nothing. On 2026-08-20 the
        # scheduled run logged "Saved 0 files to processed" and exited a
        # success, as it had each of the four mornings before — a
        # placeholder from_pdf reporting a fetch it never performed. That
        # is the lie being removed here, not a policy being declared.
        # ru: a source exists and cannot be reached. mid.ru answers every
        #     request with an F5/TSPD JavaScript anti-bot challenge shell
        #     (HTTP 200, zero content links), so the Mechanize scraper
        #     structurally cannot see the announcements. Verified against
        #     the live site on 2026-08-06.
        NO_FETCH_PATH = {
          cn: 'CN has no automated fetch path; its YAML is curated in ' \
              'data-cn',
          jp: 'JP has no automated fetch path through `ammitto fetch`: ' \
              'data-jp fetches and converts the End-User List with its ' \
              'own scripts, and this command would save zero files and ' \
              'report success. `ammitto source japan fetch meti` writes a ' \
              'standalone METI export, which is not what harmonize reads',
          ru: 'RU fetching is blocked: mid.ru serves a JavaScript ' \
              'anti-bot challenge the scraper cannot pass, so automated ' \
              'fetch does not work; refusing rather than reporting an ' \
              'empty scrape as success'
        }.freeze

        private

        # Get source model class for a source
        #
        # No require or autoload here: every source's model classes are
        # already loaded by lib/ammitto.rb's top-level `require_relative
        # 'sources/<code>/source'`, which every real load path (the CLI,
        # and every spec) runs before this method is ever called. An
        # `Ammitto::Sources.autoload :Uk, …` was tried here once and
        # removed: autoload raises NameError when the file it targets
        # reopens a top-level module of the same name it is autoloading,
        # which `sources/uk.rb` (and the other 12) does.
        # @param source [Symbol] source code
        # @return [Class, nil] the source model class
        def source_model_class_for(source)
          case source
          when :uk then Ammitto::Sources::Uk::Designations
          when :eu then Ammitto::Sources::Eu::Export
          when :un then Ammitto::Sources::Un::ConsolidatedList
          when :us then Ammitto::Sources::Us::SdnList
          when :wb then Ammitto::Sources::Wb::Response
          when :au then Ammitto::Sources::Au::SanctionsList
          when :ca then Ammitto::Sources::Ca::SanctionsList
          when :ch then Ammitto::Sources::Ch::SanctionsList
          when :tr then Ammitto::Sources::Tr::SanctionsList
          when :nz then Ammitto::Sources::Nz::SanctionsList
          when :eu_vessels then Ammitto::Sources::EuVessels::SanctionsList
          when :jp then Ammitto::Sources::Jp::SanctionsList
          when :un_vessels then Ammitto::Sources::UnVessels::SanctionsList
          end
        rescue LoadError
          nil
        end

        # Get extractor class for source
        # @param source [Symbol] source code
        # @return [Class, nil] extractor class
        def extractor_class_for(source)
          Ammitto::Extractors::Registry.get(source)
        rescue LoadError
          nil
        end
      end
    end
  end
end
