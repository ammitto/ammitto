# frozen_string_literal: true

# The models required below declare `class X < Lutaml::Model::Serializable`
# at read time and do not require it themselves yet (gem #90 is the fix
# for that). Requiring it here means this file's require list works in
# any order rather than because one entry happens to pull it in first.
require 'lutaml/model'
require_relative '../utils/iri_sanitizer'
require_relative '../utils/list_types_registry'
# `create_reason` names this. It survives without the require today
# because `sanction_reason` and `sanction_effect` both pull it in, which is
# the kind of edge this list exists to stop depending on — removing this
# line fails no example, and that is the point of stating it here.
require_relative '../ontology/value_objects/localized_string'
require_relative '../address'
require_relative '../authority'
require_relative '../birth_info'
require_relative '../identification'
require_relative '../name_variant'
require_relative '../raw_source_data'
require_relative '../sanction_effect'
require_relative '../sanction_reason'
require_relative '../sanction_regime'
require_relative '../temporal_period'

module Ammitto
  module Transformers
    # Raised when a source states a closed span of birth years whose
    # lower bound is above its upper bound.
    #
    # The span is rejected rather than reordered. Reordering would
    # publish a claim the source never made, and a reversed pair is far
    # likelier to be a source or parsing defect than an intended fact.
    # Rejection raises rather than returning nil so that "this value
    # names no span" and "this value names a span that cannot be true"
    # stay distinguishable — the second is a defect and must be visible.
    #
    # HarmonizeCommand rescues per file, records the offending filename,
    # and fails its health gate, so one bad record neither aborts the
    # run nor vanishes from it.
    class InvalidYearRangeError < StandardError; end

    # Raised when a birth-date range is a defect rather than a spelling:
    # a closed span whose lower bound is above its upper bound.
    #
    # A reversed span is rejected rather than reordered for the same
    # reason as a reversed year range: reordering would publish a claim
    # the source never made. Rejection raises rather than returning nil
    # so that "this value names no span" and "this value names a span
    # that cannot be true" stay distinguishable.
    #
    # An unrecognised or unparseable SPELLING is not a defect and does
    # not raise; see #extract_date_range. As with InvalidYearRangeError,
    # HarmonizeCommand's per-file rescue records the offending filename
    # and fails its health gate, so one bad record neither aborts the
    # run nor vanishes from it.
    class InvalidDateRangeError < StandardError; end

    # BaseTransformer provides common functionality for transforming
    # source-specific models to the harmonized Ammitto ontology.
    #
    # Each source (UK, EU, UN, US, WB) should have its own transformer
    # that inherits from this base class.
    #
    # == Normalized IRI Structure
    #
    # Entities are LIST-AGNOSTIC (can appear on multiple lists):
    #   https://www.ammitto.org/entity/{source}/{local_id}
    #
    # Entries are LIST-SPECIFIC (junction records linking entity to list):
    #   https://www.ammitto.org/entry/{source}/{list_type}/{local_id}
    #
    # @example Creating a transformer
    #   class UkTransformer < BaseTransformer
    #     def transform(designation)
    #       {
    #         entity: create_entity(designation),
    #         entry: create_entry(designation)
    #       }
    #     end
    #   end
    #
    class BaseTransformer
      # A month-precision span loses its months when it is reduced to
      # year bounds, so both endpoints must prove they name months
      # before either bound becomes a published fact.
      ENGLISH_MONTH_NAME = /
        (?:
          Jan(?:uary)? | Feb(?:ruary)? | Mar(?:ch)? | Apr(?:il)? |
          May | Jun(?:e)? | Jul(?:y)? | Aug(?:ust)? |
          Sep(?:t(?:ember)?)? | Oct(?:ober)? | Nov(?:ember)? | Dec(?:ember)?
        )
      /ix

      # Spellings read as a bare span of birth years. Every pattern is
      # ANCHORED at both ends: a span is recognised only when the WHOLE
      # value is one.
      #
      # A day-precision span ("28 Feb 1962 to 28 Feb 1963") is NOT here.
      # It keeps its days through FULL_DATE_SPAN, which publishes date
      # bounds and derives year bounds from them, so nothing is lost.
      #
      # A month-precision span ("Mar 1980 to Mar 1981") IS here, and the
      # months are lost. That is the lesser loss: date bounds cannot hold
      # it without inventing a day, so the alternative is not keeping the
      # months but publishing nothing at all, which is what this shape
      # did before. The year span it yields is true, and it is the same
      # trade already accepted for "1955 to 1957". Anchoring alone does
      # not earn that trade: an endpoint of ANY word plus a year is
      # anchored too, and admits "circa 1962 to circa 1964" — a
      # qualified span, which is the grammar FULL_DATE_SPAN also
      # declines. Only a named month says the value carries month
      # precision, so only a named month may be dropped for its year.
      #
      # The hyphen spelling ("1962-1964") is deliberately absent. It
      # appears in none of the corpora that state spans as text — 0 of
      # 5795 distinct OFAC dateOfBirth values, none in the DFAT corpus —
      # and the EU states its bounds as XML attributes rather than text.
      # Such a value still yields no scalar year, via #multiple_years?,
      # so it is an unsupported input rather than a misread one.
      YEAR_RANGE_PATTERNS = [
        /\A(?:approximately\s*:?\s*)?between\s+(\d{4})\s+and\s+(\d{4})\z/i,
        /\A(\d{4})\s+to\s+(\d{4})\z/i,
        /
          \A#{ENGLISH_MONTH_NAME}\s+(\d{4})\s+to\s+
          #{ENGLISH_MONTH_NAME}\s+(\d{4})\z
        /ix
      ].freeze

      # Connectors that join the two halves of a span. Used to tell a
      # span from a single point in time before Date._parse is asked for
      # a date, because Date._parse reads only the first half and would
      # publish one endpoint as though the source had stated it alone.
      SPAN_CONNECTOR = /\s+(?:to|and)\s+/i

      # A full-date span whose endpoints are each a complete date, e.g.
      # "01 Jan 1962 to 31 Dec 1962". OFAC writes this in dozens of
      # spellings and it must not become its opening date; both
      # endpoints are published instead, as the date bounds.
      #
      # Deliberately strict: both endpoints must be complete. An
      # abbreviated tail ("01 Jan 1973 to 31 Dec") states no complete
      # upper bound, and a qualified value ("circa ...") is a different
      # grammar that has not been designed.
      FULL_DATE_SPAN = /
        \A
        (?<from>\d{1,2}\s+[[:alpha:]]{3,9}\s+\d{4})
        \s+to\s+
        (?<to>\d{1,2}\s+[[:alpha:]]{3,9}\s+\d{4})
        \z
      /ix

      attr_reader :source_code, :list_type

      # Initialize with source code and optional list type
      # @param source_code [Symbol] the source identifier (e.g., :uk, :eu)
      # @param list_type [String, nil] optional list type (e.g., "consolidated-list")
      def initialize(source_code, list_type: nil)
        @source_code = source_code.to_sym
        @list_type = list_type || default_list_type
      end

      # Transform source model to ontology models
      # @param source_model [Object] the source-specific model
      # @return [Hash] { entity: Entity, entry: SanctionEntry }
      def transform(source_model)
        raise NotImplementedError, 'Subclasses must implement #transform'
      end

      # Transform a collection of source models
      # @param source_models [Array<Object>] collection of source models
      # @return [Array<Hash>] array of transformation results
      def transform_all(source_models)
        source_models.map { |model| transform(model) }
      end

      protected

      # Generate a unique entity ID (LIST-AGNOSTIC).
      # Entities can appear on multiple lists, so no list_type in IRI.
      #
      # @param local_id [String] the local entity identifier
      # @return [String] the full entity URI
      # @raise [Utils::IriSanitizer::MissingLocalIdError] when local_id
      #   is blank or sanitizes to nothing
      #
      # @example
      #   generate_entity_id("mitsubishi-heavy-industries")
      #   # => "https://www.ammitto.org/entity/cn/mitsubishi-heavy-industries"
      #
      def generate_entity_id(local_id)
        Utils::IriSanitizer.entity_iri(source_code.to_s, local_id)
      end

      # Generate a unique entry ID (LIST-SPECIFIC).
      # Entries link entities to specific lists.
      #
      # @param local_id [String] the local entry identifier
      # @param entry_list_type [String, nil] optional list type override
      # @return [String] the full entry URI
      # @raise [Utils::IriSanitizer::MissingLocalIdError] when local_id
      #   is blank or sanitizes to nothing
      #
      # @example
      #   generate_entry_id("mitsubishi-heavy-industries")
      #   # => "https://www.ammitto.org/entry/cn/import-export-control-list/mitsubishi-heavy-industries"
      #
      def generate_entry_id(local_id, entry_list_type: nil)
        effective_list_type = entry_list_type || list_type || default_list_type
        Utils::IriSanitizer.entry_iri(source_code.to_s, effective_list_type, local_id)
      end

      # Generate a list type IRI.
      #
      # @param list_type_id [String, nil] optional list type override
      # @return [String] the full list URI
      #
      def generate_list_id(list_type_id: nil)
        effective_list_type = list_type_id || list_type || default_list_type
        Utils::IriSanitizer.list_type_iri(source_code.to_s, effective_list_type)
      end

      # Generate an announcement ID (LIST-AGNOSTIC).
      #
      # @param local_id [String] the local announcement identifier
      # @return [String] the full announcement URI
      # @raise [Utils::IriSanitizer::MissingLocalIdError] when local_id
      #   is blank or sanitizes to nothing
      #
      def generate_announcement_id(local_id)
        Utils::IriSanitizer.announcement_iri(source_code.to_s, local_id)
      end

      # Generate a legal instrument ID (LIST-AGNOSTIC).
      #
      # @param local_id [String] the local legal instrument identifier
      # @return [String] the full legal instrument URI
      # @raise [Utils::IriSanitizer::MissingLocalIdError] when local_id
      #   is blank or sanitizes to nothing
      #
      def generate_legal_instrument_id(local_id)
        Utils::IriSanitizer.legal_instrument_iri(source_code.to_s, local_id)
      end

      # Get the default list type for this source.
      #
      # @return [String, nil] the default list type or nil
      #
      def default_list_type
        Utils::ListTypesRegistry.default_list_type(source_code.to_s)
      end

      # Get all available list types for this source.
      #
      # @return [Array<String>] list of available list types
      #
      def available_list_types
        Utils::ListTypesRegistry.list_types_for(source_code.to_s)&.keys || []
      end

      # Get the authority for this source
      # @return [Authority] the authority object
      def authority
        @authority ||= Ammitto::Authority.find(source_code.to_s)
      end

      # Sanitize an ID for use in URIs
      # @param id [String] the raw ID
      # @return [String] sanitized ID
      def sanitize_id(id)
        Utils::IriSanitizer.sanitize(id)
      end

      # Parse a date string safely
      # @param date_str [String, Date, nil] the date string or Date object
      # @return [Date, nil] parsed date or nil
      def parse_date(date_str)
        return nil if date_str.nil?
        return date_str if date_str.is_a?(Date)
        return nil if date_str.to_s.empty?

        begin
          Date.parse(date_str.to_s)
        rescue Date::Error
          nil
        end
      end

      # Create a NameVariant from name parts
      # @param full_name [String, nil] full name
      # @param first_name [String, nil] first name
      # @param middle_name [String, nil] middle name
      # @param last_name [String, nil] last name
      # @param script [String, nil] script (Latn, Cyrl, etc.)
      # @param is_primary [Boolean] whether this is the primary name
      # @return [NameVariant] the name variant
      def create_name_variant(full_name: nil, first_name: nil, middle_name: nil,
                              last_name: nil, script: nil, is_primary: false)
        Ammitto::NameVariant.new(
          full_name: full_name,
          first_name: first_name,
          middle_name: middle_name,
          last_name: last_name,
          script: script,
          is_primary: is_primary
        )
      end

      # Create an Address from address parts
      # @param street [String, nil] street address
      # @param city [String, nil] city
      # @param state [String, nil] state/province
      # @param country [String, nil] country name
      # @param country_iso_code [String, nil] ISO country code
      # @param postal_code [String, nil] postal code
      # @return [Address] the address
      def create_address(street: nil, city: nil, state: nil, country: nil,
                         country_iso_code: nil, postal_code: nil)
        Ammitto::Address.new(
          street: street,
          city: city,
          state: state,
          country: country,
          country_iso_code: country_iso_code,
          postal_code: postal_code
        )
      end

      # Create a BirthInfo from birth data.
      #
      # Invariants:
      #
      # * BirthInfo#date is set only when the source states a complete
      #   day-month-year; a bare or partial year rides in BirthInfo#year
      #   and is never padded into an invented date. A span never
      #   becomes its opening endpoint.
      # * A span of complete dates rides in BirthInfo#date_range_from /
      #   #date_range_to, and publishes its endpoint years through the
      #   year-range fields as well, so year-only indexes keep the
      #   record. Those derived bounds supplement the source claim; they
      #   do not replace it.
      # * A date span wholly inside one year also retains that exact
      #   year in #year. No scalar year is emitted when it crosses years.
      # * A span of years rides in BirthInfo#year_range_from /
      #   #year_range_to, and while one is present both #date and #year
      #   stay nil. Neither bound is the birth year, so filling #year
      #   with an endpoint would assert something the source never said.
      # * circa is carried through from the source, never inferred from
      #   the presence of a span.
      #
      # Year bounds passed by a caller are authoritative, as the EU and
      # DFAT state them in fields of their own: when either is given the
      # date string is not searched for a span at all, and a missing
      # bound stays missing rather than being filled from the string.
      #
      # There is deliberately no caller-stated pair for the DATE bounds.
      # No source states a complete-date span in fields of its own — OFAC
      # writes it into the value itself — so the only way to reach the
      # date bounds is FULL_DATE_SPAN, whose endpoints this method parses
      # and validates. Adding the keywords back would reopen the ordering
      # question of which pair wins, and answering it by deriving year
      # bounds from the dates silently discarded whichever year bounds
      # the caller had stated.
      #
      # @param date [String, Date, nil] birth date
      # @param circa [Boolean] whether the date is approximate
      # @param city [String, nil] birth city
      # @param region [String, nil] birth region/state
      # @param country [String, nil] birth country
      # @param country_iso_code [String, nil] ISO country code
      # @param year [Integer, String, nil] source-stated birth year
      # @param year_range_from [Integer, String, nil] lower year bound
      # @param year_range_to [Integer, String, nil] upper year bound
      # @raise [InvalidDateRangeError] when a closed date span read from
      #   the value runs backwards
      # @raise [InvalidYearRangeError] when a year bound is not a year,
      #   or a closed year span runs backwards
      # @return [BirthInfo] the birth info
      def create_birth_info(date: nil, circa: false, city: nil, region: nil, country: nil,
                            country_iso_code: nil, year: nil,
                            year_range_from: nil, year_range_to: nil)
        date_bounds = nil
        year_bounds = stated_year_range(year_range_from, year_range_to)

        unless year_bounds
          date_bounds = extract_date_range(date)
          year_bounds = extract_year_range(date) unless date_bounds
        end

        place = [circa, city, region, country, country_iso_code]
        return birth_info_for_date_range(date_bounds, *place) if date_bounds
        return birth_info_for_range(year_bounds, *place) if year_bounds

        parsed_date = parse_complete_date(date)

        Ammitto::BirthInfo.new(
          date: parsed_date,
          circa: circa,
          city: city,
          region: region,
          country: country,
          country_iso_code: country_iso_code,
          year: normalize_year(year) || parsed_date&.year ||
                extract_birth_year(date)
        )
      end

      # A date span publishes its complete endpoints and repeats their
      # years for discovery. When both endpoints share a year the whole
      # interval lies inside it, so retaining that scalar reads out a
      # fact the source stated twice rather than inventing a day.
      # @param bounds [Array<Date, nil>] validated [from, to]
      # @return [BirthInfo] the birth info
      def birth_info_for_date_range(bounds, circa, city, region, country, country_iso_code)
        lower, upper = bounds
        exact_year = lower.year if lower && upper && lower.year == upper.year

        Ammitto::BirthInfo.new(
          date: nil,
          year: exact_year,
          date_range_from: lower,
          date_range_to: upper,
          year_range_from: lower&.year,
          year_range_to: upper&.year,
          circa: circa,
          city: city,
          region: region,
          country: country,
          country_iso_code: country_iso_code
        )
      end

      # A span of years suppresses both scalars: date and year are the
      # source's single-value claims, and a span makes neither.
      # @param bounds [Array<Integer, nil>] validated [from, to]
      # @return [BirthInfo] the birth info
      def birth_info_for_range(bounds, circa, city, region, country, country_iso_code)
        Ammitto::BirthInfo.new(
          date: nil,
          year: nil,
          year_range_from: bounds.first,
          year_range_to: bounds.last,
          circa: circa,
          city: city,
          region: region,
          country: country,
          country_iso_code: country_iso_code
        )
      end

      # Bounds of a complete-date span stated as one string, or nil when
      # the value names no such span. Recognition stays anchored (see
      # FULL_DATE_SPAN), so month-only, abbreviated and qualified spans
      # still cannot be upgraded into facts they do not contain.
      #
      # An endpoint matching the SHAPE but naming no real calendar day —
      # "31 Feb 1962", or OFAC's zero-padded "00 Jan 1962" — means the
      # value does not state a complete-date span, so it yields nil and
      # the record publishes nothing.
      #
      # For a SAME-YEAR span that is a deliberate NARROWING: the rule
      # this one replaced matched on the two year captures alone and
      # never looked at the days, so "00 Jan 1962 to 31 Dec 1962" used
      # to surrender year 1962. Date bounds need endpoints that name
      # real days, so the shape now publishes nothing instead. It is
      # accepted rather than repaired because recovering the years from
      # a value whose days are unreadable is a second grammar, and no
      # evidence says the shape occurs; see the spec of the same name.
      #
      # Yielding nil rather than raising mirrors extract_year_range,
      # whose text path also stays silent on an unrecognised spelling.
      # Raising is reserved for a closed span that runs backwards, which
      # is a value that cannot be true rather than one merely unread.
      # @param value [Object] candidate date string
      # @raise [InvalidDateRangeError] when a closed span runs backwards
      # @return [Array<Date>, nil] validated bounds, or nil
      def extract_date_range(value)
        return nil unless value.is_a?(String)

        match = FULL_DATE_SPAN.match(value.strip)
        return nil unless match

        lower = parse_complete_date(match[:from])
        upper = parse_complete_date(match[:to])
        return nil unless lower && upper

        validate_date_range(lower, upper)
      end

      # A closed span must run forwards. Only a closed one can: an open
      # bound has nothing to be out of order with.
      # @param lower [Date, nil] lower bound
      # @param upper [Date, nil] upper bound
      # @raise [InvalidDateRangeError] when a closed span runs backwards
      # @return [Array<Date, nil>] the bounds, unchanged
      def validate_date_range(lower, upper)
        if lower && upper && lower > upper
          raise InvalidDateRangeError,
                "birth date range runs backwards: #{lower} > #{upper}"
        end

        [lower, upper]
      end

      # Bounds a caller stated outright, as the EU does through its
      # yearRangeFrom / yearRangeTo XML attributes.
      #
      # Presence is decided BEFORE normalization, so a stated bound that
      # is not a year cannot quietly become "no bound stated" and hand
      # authority back to the date string. That fallback would let a
      # record publish a span extracted from its text while the bounds
      # the source actually stated were dropped unmentioned.
      # @param from [Integer, String, nil] lower bound
      # @param to [Integer, String, nil] upper bound
      # @raise [InvalidYearRangeError] when a bound is not a year, or a
      #   closed span runs backwards
      # @return [Array<Integer, nil>, nil] validated bounds, or nil
      def stated_year_range(from, to)
        return nil if from.nil? && to.nil?

        validate_year_range(year_bound(from), year_bound(to))
      end

      # @param value [Integer, String, nil] a stated bound
      # @raise [InvalidYearRangeError] when stated but not a year
      # @return [Integer, nil]
      def year_bound(value)
        return nil if value.nil?

        normalize_year(value) ||
          raise(InvalidYearRangeError,
                "birth year range bound is not a year: #{value.inspect}")
      end

      # Bounds of a span stated as text, or nil when the value names no
      # span. Recognition is anchored (see YEAR_RANGE_PATTERNS), so a
      # value carrying finer precision is left for the scalar path,
      # where the span guards then keep it from becoming a false date.
      # @param value [Object] candidate date string
      # @raise [InvalidYearRangeError] when a closed span runs backwards
      # @return [Array<Integer>, nil] validated bounds, or nil
      def extract_year_range(value)
        return nil unless value.is_a?(String)

        str = value.strip
        pattern = YEAR_RANGE_PATTERNS.find { |candidate| candidate.match?(str) }
        return nil unless pattern

        match = pattern.match(str)
        validate_year_range(match[1].to_i, match[2].to_i)
      end

      # A closed span must run forwards. Only a closed one can: an open
      # bound has nothing to be out of order with.
      # @param lower [Integer, nil] lower bound
      # @param upper [Integer, nil] upper bound
      # @raise [InvalidYearRangeError] when a closed span runs backwards
      # @return [Array<Integer, nil>] the bounds, unchanged
      def validate_year_range(lower, upper)
        if lower && upper && lower > upper
          raise InvalidYearRangeError,
                "birth year range runs backwards: #{lower} > #{upper}"
        end

        [lower, upper]
      end

      # Parse a value into a Date only when it states day, month and year.
      # Partial expressions ("1975", "Oct 1988", "00/00/1963") yield nil
      # instead of a date padded with invented components. Date instances
      # pass through: the caller already resolved them.
      #
      # A span yields nil too. Date._parse reads only the first half of
      # "28 Feb 1962 to 28 Feb 1963" and of "01 Jan 1973 to 31 Dec 1973",
      # so without the guard the opening endpoint was published as
      # though the source had stated it as the birth date — and for the
      # "01 Jan" shape, which OFAC writes 37 distinct ways to mean
      # "some day that year", that is the invented January date this
      # gem already set out to stop asserting.
      # @param value [Date, String, nil]
      # @return [Date, nil]
      def parse_complete_date(value)
        return value if value.is_a?(Date)

        str = value.to_s.strip
        return nil if str.empty?
        return nil if date_span?(str)

        parts = Date._parse(str)
        return nil unless parts[:year] && parts[:mon] && parts[:mday]

        Date.new(parts[:year], parts[:mon], parts[:mday])
      rescue Date::Error
        nil
      end

      # Whether a value states a span rather than one point in time:
      # some connector in it splits the value into a dated first half
      # and a second half that continues the date. "1962 to 1964",
      # "28 Feb 1962 to 28 Feb 1963", "Between 1959 and 1965".
      #
      # The FIRST half must name a year and the second must carry at
      # least a digit. That asymmetry is deliberate. Requiring a year on
      # both sides would read "01 Jan 1973 to 31 Dec" as a single date
      # and publish 1 January 1973 — a date the source never stated —
      # because Date._parse reads the opening half and stops. This
      # predicate exists to answer "is this NOT one complete date", and
      # an abbreviated span is not one, whatever else it may be. The
      # weaker second-half test costs nothing measurable: over the 5795
      # distinct OFAC dateOfBirth values and the 12433 distinct
      # birth-field strings in the fetched corpora it classifies exactly
      # the same values as the both-halves rule.
      #
      # Requiring a year in the FIRST half is what keeps ordinary values
      # parsing: "Jan and Feb 1970" has a yearless first half and is not
      # a span.
      #
      # EVERY connector is tried, not only the first, so a value whose
      # opening connector is not the span connector still reads
      # correctly.
      #
      # This is broader than #multiple_years? on purpose:
      # "01 Jan 1973 to 31 Dec 1973" names one distinct year twice, and
      # a uniqueness test cannot see the span in it.
      #
      # Recognising a span is not the same as publishing one: only the
      # anchored YEAR_RANGE_PATTERNS and FULL_DATE_SPAN produce bounds.
      # A span recognised here but matched by neither publishes nothing,
      # which is the point — it is rejection of a value known to be
      # misparsed, not support for a spelling.
      #
      # @param value [Object] candidate date string
      # @return [Boolean]
      def date_span?(value)
        return false unless value.is_a?(String)

        str = value.strip
        span_connector_offsets(str).any? do |start, finish|
          /\d{4}/.match?(str[0...start]) && /\d/.match?(str[finish..])
        end
      end

      # @param str [String] candidate date string
      # @return [Array<Array<Integer>>] each connector's [start, end]
      def span_connector_offsets(str)
        offsets = []
        str.scan(SPAN_CONNECTOR) { offsets << Regexp.last_match.offset(0) }
        offsets
      end

      # Year stated by a partial date string ("1975", "circa 1975",
      # "Oct 1988", "00/00/1963"). A span such as "1962 to 1964" or
      # "01 Jan 1973 to 31 Dec 1973" names no single year and yields
      # nil: a recognised span rides in the range fields instead, and an
      # unrecognised one is a shape this gem does not publish. Both
      # rejections are stated here rather than left to Date._parse,
      # which returns no year for some span spellings only incidentally
      # and happily returns one for others.
      # @param value [Object] candidate date string
      # @return [Integer, nil]
      def extract_birth_year(value)
        return nil unless value.is_a?(String)

        str = value.strip.sub(/\A(?:circa|approximately|c\.?)\s*/i, '')
        return nil if date_span?(str) || multiple_years?(str)
        return str.to_i if /\A\d{4}\z/.match?(str)

        year = Date._parse(str)[:year]
        year&.positive? ? year : nil
      end

      # Whether a date string names more than one year — "1962 to 1964",
      # "between 1962 and 1964", "1962-1964". Such a string states a
      # range, not a birth year. Years are matched on word boundaries so
      # a run of digits ("19620101") is not read as two of them.
      # @param value [String] date string, circa marker already stripped
      # @return [Boolean]
      def multiple_years?(value)
        value.scan(/\b\d{4}\b/).uniq.size > 1
      end

      # Whether a source date string marks itself approximate
      # ("circa 1960", "c. 1955", "c 1955", "approximately 1965").
      # The bare "c" form is recognized because extract_birth_year
      # strips it and au's FlexibleDate parser reads it as circa; without
      # it "c 1955" yielded a year with circa left false.
      # @param value [Object] candidate date string
      # @return [Boolean]
      def circa_string?(value)
        value.is_a?(String) &&
          value.strip.match?(/\A(?:circa|approximately|c\.?)\s/i)
      end

      # Coerce a source-stated year to a positive Integer
      # @param value [Integer, String, nil]
      # @return [Integer, nil]
      def normalize_year(value)
        year = value.is_a?(Integer) ? value : value.to_s[/\A\d{4}\z/]&.to_i
        year&.positive? ? year : nil
      end

      # Create a SanctionRegime
      # @param name [String, nil] regime name
      # @param code [String, nil] regime code
      # @param description [String, nil] regime description
      # @return [SanctionRegime] the regime
      def create_regime(name: nil, code: nil, description: nil)
        Ammitto::SanctionRegime.new(
          name: name,
          code: code,
          description: description
        )
      end

      # Create a TemporalPeriod
      # @param listed_date [String, Date, nil] listing date
      # @param effective_date [String, Date, nil] effective date
      # @param expiry_date [String, Date, nil] expiry date
      # @param last_updated [String, nil] last update timestamp
      # @return [TemporalPeriod] the period
      def create_period(listed_date: nil, effective_date: nil, expiry_date: nil,
                        last_updated: nil)
        Ammitto::TemporalPeriod.new(
          listed_date: listed_date.is_a?(Date) ? listed_date : parse_date(listed_date),
          effective_date: effective_date.is_a?(Date) ? effective_date : parse_date(effective_date),
          expiry_date: expiry_date.is_a?(Date) ? expiry_date : parse_date(expiry_date),
          is_indefinite: expiry_date.nil?,
          last_updated: last_updated
        )
      end

      # Create a SanctionEffect
      # @param effect_type [String] the effect type
      # @param scope [String, nil] the scope (full, partial, limited)
      # @param description [String, nil] description
      # @return [SanctionEffect] the effect
      def create_effect(effect_type:, scope: 'full', description: nil)
        Ammitto::SanctionEffect.new(
          effect_type: effect_type,
          scope: scope,
          description: description
        )
      end

      # Create a SanctionReason
      # @param category [String] the reason category
      # @param description [String, nil] description text
      # @param language [String] language code (default: 'en')
      # @return [SanctionReason] the reason
      def create_reason(category:, description: nil, language: 'en')
        descriptions = []
        if description
          descriptions << Ammitto::Ontology::ValueObjects::LocalizedString.new(
            value: description,
            language: language,
            is_primary: true
          )
        end

        Ammitto::SanctionReason.new(
          category: category,
          description: descriptions
        )
      end

      # Create a RawSourceData
      # @param source_file [String, nil] source file name
      # @param source_format [String] format (xml, json, etc.)
      # @param raw_content [String, nil] raw content
      # @param source_specific_fields [Hash, nil] source-specific data
      # @return [RawSourceData] the raw source data
      def create_raw_source_data(source_file: nil, source_format: 'xml',
                                 raw_content: nil, source_specific_fields: nil)
        Ammitto::RawSourceData.new(
          source_file: source_file,
          source_format: source_format,
          raw_content: raw_content,
          source_specific_fields: source_specific_fields || {}
        )
      end

      # Create an Identification
      # @param type [String, nil] document type
      # @param number [String, nil] document number
      # @param issuing_country [String, nil] issuing country
      # @param note [String, nil] additional notes
      # @return [Identification] the identification
      def create_identification(type: nil, number: nil, issuing_country: nil,
                                note: nil)
        Ammitto::Identification.new(
          type: type,
          number: number,
          issuing_country: issuing_country,
          note: note
        )
      end
    end
  end
end
