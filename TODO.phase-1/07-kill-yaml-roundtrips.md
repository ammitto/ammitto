= B: replace from_yaml(data.to_yaml) round-trips (G3)
Defect: anchor re-emission into aliases-disabled loader; jp 15 files crash, 13 sources latent.
Fix: from_hash everywhere (cn pattern). Accept: anchored fixture passes on every source path. Size M.
