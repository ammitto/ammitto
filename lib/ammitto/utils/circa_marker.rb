# frozen_string_literal: true

module Ammitto
  module Utils
    # The grammar for the prefix a source writes to mark a date
    # approximate, shared by every layer that reads one.
    #
    # It lives here rather than on Transformers::BaseTransformer, where it
    # was written, because Sources::Au::FlexibleDate needs the same rule
    # and a source model must not reach into the transformer layer to get
    # it: sources are parsed before transformers run, so the dependency
    # would point backwards. Copying the pattern instead was the option
    # rejected outright -- two grammars reading the same prefix
    # differently is the defect this constant was extracted to end, and
    # duplicating it would have recreated that defect one layer down.
    #
    # Included for its constants, not for behaviour. Each layer keeps its
    # own reader: the transformer strips the marker off a string it hands
    # to Date._parse, FlexibleDate sets a flag and a precision on a parse
    # it is building. What may not differ is which prefixes count.
    module CircaMarker
      # The prefix a source writes to mark a date approximate, in the
      # spellings OFAC and DFAT use.
      #
      # ONE constant, read by every stripper and every detector, because
      # they are two halves of a single decision and a spelling that only
      # one of them recognises publishes an approximate year as an exact
      # one. They diverged twice. In the transformer: the stripper
      # accepted the marker glued to its year, the detector demanded
      # whitespace, so "c.1955" yielded year 1955 with circa left false.
      # In FlexibleDate: the test was start_with?("circa", "c.", "c"),
      # which never listed "approximately" at all, so "Approximately
      # 1968" -- the spelling DFAT actually writes, and the only one it
      # writes -- was published as an exact 1968.
      #
      # Every spelling must be followed by whitespace, a digit or a colon.
      # The boundary is what separates the marker from a word that merely
      # starts like one: without it "China 1955" is an approximate 1955
      # (bare "c"), and so are "circadian 1955" and "c.China 1955".
      #
      # The colon is not decoration. Both layers already accept
      # "Approximately: Between 1959 and 1965" as a span, so DFAT writes
      # the marker that way and the span grammars have always known it;
      # the scalar detectors did not, and published that span with circa
      # false. "approximately: 1955" was worse, yielding an exact 1955.
      #
      # A digit satisfies the boundary as well as a space, because
      # refusing to strip "c1955" does not stop it yielding a year --
      # Date._parse reads 1966 out of "c07 Jul 1966" regardless -- and the
      # flag would be false again. No glued form occurs in any corpus (0 of
      # 5827 distinct OFAC dateOfBirth values, 0 across all fourteen data
      # repos, measured 2026-09-08), so the reading is chosen on which
      # failure is worse: asserting a year the source hedged is worse than
      # hedging one it asserted.
      CIRCA_MARKER = /\A(?:circa|approximately|c\.?)(?=[\s:\d])\s*:?\s*/i

      # A value that OPENS like a marker without satisfying that boundary.
      # Such a value is not a spelling this gem reads, and reading it is
      # not harmless: Date._parse finds 1988 in "c.Oct 1988" whatever the
      # prefix means, and a detector would then call that year exact,
      # which is the disagreement CIRCA_MARKER exists to prevent. Declining
      # the year costs nothing measurable -- no value in any of the
      # fourteen corpora opens with "c" or "approximately" other than
      # "circa " itself, 2026-09-08 -- and losing a year is the safer of
      # the two failures.
      #
      # Tightening the boundary without also adopting this is the trap.
      # FlexibleDate's old prefix test had no boundary, so it flagged
      # "c.Oct 1988" circa by accident; CIRCA_MARKER alone would decline
      # the marker and then let the month/year branch read "Oct 1988" as
      # an exact October 1988. That is a worse reading than the one being
      # replaced, which is why both constants move together.
      MARKER_LIKE = /\A(?:circa|approximately|c)/i
    end
  end
end
