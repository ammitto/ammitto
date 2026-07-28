= A0: announcement-shape detection guards (ch/us/uk)
Defect: announcement-format YAML parsed as legacy models -> ch crash (G4), us silent garbage (G5).
Fix: detect announcement shape, fail with a useful error naming the format; NO ingestion yet (A-JP deferred).
Accept: ch/us slices fail loudly with actionable message, exit nonzero. Size S-M.
