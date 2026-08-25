# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in ammitto.gemspec
gemspec

gem 'rake'
gem 'rspec', '~> 3.0'
# Pinned to a minor. Gemfile.lock is gitignored, so CI resolves whatever
# RuboCop is newest at the time it runs, while a developer's bundle can
# stay where it was. `.rubocop.yml` sets `NewCops: enable`, which opts in
# to pending cops automatically — so a RuboCop release can turn CI red on
# code nobody touched. 1.90.0 did exactly that with Style/DirectiveScope,
# over five pre-existing directive regions across four files. Raise this
# deliberately, with those regions rewritten and re-verified in the same
# change: 1.88 does not honour the `disable-next` form 1.90 asks for, so
# the two cannot be straddled.
gem 'rubocop', '~> 1.88.0'
gem 'rubocop-rspec', '~> 3.10.0'
gem 'vcr'
gem 'webmock'

# Neo4j driver for direct graph database access
gem 'neo4j-ruby-driver'
# Lock connection_pool to compatible version (3.x breaks neo4j-ruby-driver)
gem 'connection_pool', '~> 2.5'
