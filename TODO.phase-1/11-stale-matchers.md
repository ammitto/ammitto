= I: fix schema-stale matchers (G15, G25)
Defect: cn list matching vs slugs -> entry/cn/unknown; vessels registry hyphen vs underscore keys -> list unknown.
Where: cn/announcement.rb:120-131; utils/list_types_registry.rb:161-226. Accept: cn entries carry real list ids; eu_vessels entries leave 'unknown'. Size M.
