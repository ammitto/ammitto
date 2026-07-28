= Nonzero exit on fetch source failure
Defect: fetch reports success while sources fail (root cause of silent data loss).
Fix: exe/ammitto fetch exits nonzero when any requested source fails.
Accept: fetch cn (hard-block) exits 1; passing sources unaffected. Size S.
