# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"

gem "pry"
gem "simplecov"

# Local checkouts while the gems are developed inside common/gems/.
# Switch to `github: "verse-rb/..."` once published.
gem "verse-core", github: "verse-rb/verse-core", branch: "master"
gem "verse-schema", "~> 1.2"

# Not runtime dependencies of the gem — `tracing: otel` loads them lazily and
# services opt in via their own Gemfile. Here only so the otel-mode specs run.
gem "sentry-opentelemetry"
gem "verse-otel", github: "verse-rb/verse-otel", branch: "master"

# Exercised by the profiling specs.
gem "stackprof"

# Sentry builds its Request interface out of a rack env; in production rack
# arrives through verse-http. Only the HTTP-exposition specs need it.
gem "rack"
