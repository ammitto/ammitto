= Scope supporting/instruments dirs per source (G8)
Defect: find_instruments_dir/find_supporting_dir hardcode data-cn; cn docs injected into every source.
Where: cli/harmonize_command.rb:512,536. Accept: non-cn trees carry no cn nodes. Size S.
