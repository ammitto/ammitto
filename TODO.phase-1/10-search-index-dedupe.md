= E: dedupe search index + facets (G12, G10)
Defect: endpoints disagree — index carries duplicate rows (cn 390 vs 322).
Where: search_index_exporter.rb:75-113. Accept: index rows == unique ids per source; log counts consistent. Size M.
