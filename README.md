# verse-sentry

[Sentry](https://sentry.io) integration for [Verse](https://github.com/verse-rb) services.

Error capture with rich context on every exposition (auth metadata, role and
user tags, sanitized params) — including event-subscriber errors that Verse
swallows after logging — plus three tracing modes.

## Usage

```ruby
# Gemfile
gem "verse-sentry"
```

```yaml
# config/config.yml
plugins:
  - plugin: sentry
    config:
      dsn: <%= ENV["SENTRY_DSN"] %>   # empty/missing DSN disables everything
      environment: <%= ENV["SENTRY_ENVIRONMENT"] %>  # empty/missing: APP_ENVIRONMENT
      tracing: none                    # none | native | otel
      traces_sample_rate: <%= ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", 0.1) %>
```

The environment reported to Sentry is `environment` when set, otherwise
`APP_ENVIRONMENT`. Set it when several installs share a DSN, so each reports
its own name. Verse 4xx
business errors (NotFound, ValidationFailed, …) are excluded from issue
creation by default; override with `excluded_exceptions`.

## Optional dependencies

`sentry-ruby` is the only hard dependency. Everything below is loaded lazily
and only when the matching config asks for it — add it to your service's
Gemfile, and the plugin will tell you (loudly, at boot) if it is missing.

| Gem                    | Needed for                              |
| ---------------------- | --------------------------------------- |
| `verse-otel`           | `tracing: otel`                         |
| `sentry-opentelemetry` | `tracing: otel`                         |
| `stackprof`            | `profiles_sample_rate` > 0              |

Nothing extra is required for `tracing: none` or `tracing: native` — Sequel
spans in native mode work off the Sequel you already have.

## Sentry Logs and Profiles

```yaml
config:
  enable_logs: true          # mirror Verse.logger (stdlib Logger) into Sentry Logs
  profiles_sample_rate: 0.1  # Sentry Profiles; relative to traces_sample_rate
```

- `enable_logs` turns on Sentry's structured logs and prepends the SDK's
  stdlib-Logger hook, so everything logged through `Verse.logger` appears in
  Sentry Logs (severity filtering follows the logger's own level).
- `profiles_sample_rate` requires the `stackprof` gem in your service's
  Gemfile and a tracing mode of `native` or `otel` — profiles are captured
  per transaction, so with `tracing: none` the setting is ignored.

## Tracing modes

- `none` — error tracking only.
- `native` — the Sentry SDK's own tracing: one transaction per exposition and
  child spans for every Sequel query. No OpenTelemetry gems needed.
- `otel` — bridge [verse-otel](https://github.com/verse-rb/verse-otel)'s
  OpenTelemetry spans into Sentry. Requires the `verse-otel` and
  `sentry-opentelemetry` gems, plus the `otel` plugin declared in config.yml
  (order does not matter). Errors arrive automatically linked to their
  traces, and the SDK's own envelope uploads are excluded from tracing.

```ruby
# Gemfile — otel mode
gem "verse-sentry"
gem "verse-otel"
gem "sentry-opentelemetry"
```

```yaml
# otel mode example
plugins:
  - plugin: sentry
    config:
      dsn: <%= ENV["SENTRY_DSN"] %>
      tracing: otel
      traces_sample_rate: 1.0
  - plugin: otel
    config:
      instrumentations: [rack, sinatra, net_http, pg, concurrent_ruby]
```

## Development

```
bundle install
bundle exec rspec
```
