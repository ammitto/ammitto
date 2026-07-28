= C: IriSanitizer raises on nil local ids (G2,G5,G6)
Defect: nil -> 'unknown' collapse silently merges distinct entities (tr 37, us, jp).
Where: utils/iri_sanitizer.rb:90-102. Accept: nil id raises with source context; tr slice fails loudly pre-backfill. Size M.
