# frozen_string_literal: true

require "verse/schema"

module Verse
  module Sentry
    Config = Struct.new(
      :dsn,
      :environment,
      :tracing,
      :traces_sample_rate,
      :profiles_sample_rate,
      :enable_logs,
      :send_default_pii,
      :excluded_exceptions,
      keyword_init: true
    )

    class Config
      TRACING_MODES = %i[none native otel].freeze

      # Verse business errors rendered as 4xx HTTP responses — not defects.
      # Providing `excluded_exceptions` in the plugin config replaces this list.
      DEFAULT_EXCLUDED_EXCEPTIONS = %w[
        Verse::Error::ValidationFailed
        Verse::Error::NotFound
        Verse::Error::RecordNotFound
        Verse::Error::BadRequest
        Verse::Error::Unauthorized
        Verse::Error::Authorization
        Verse::Error::AuthenticationFailed
      ].freeze

      Schema = Verse::Schema.define do
        # Nil-tolerant: `dsn: <%= ENV["SENTRY_DSN"] %>` in config.yml yields
        # nil when the variable is unset, which must mean "disabled".
        field(:dsn, [String, NilClass]).default("")
        # Nil-tolerant for the same reason: `environment: <%= ENV["SENTRY_ENVIRONMENT"] %>`
        # yields nil when unset, and nil or empty falls back to APP_ENVIRONMENT.
        field(:environment, [String, NilClass]).default(nil)
        field(:tracing, Symbol)
          .default(:none)
          .rule("must be one of #{TRACING_MODES.join(", ")}") { |v| TRACING_MODES.include?(v) }
        field(:traces_sample_rate, Float).default(0.1)
        # Sentry Profiles: sampled relative to traces_sample_rate; needs the
        # `stackprof` gem and tracing :native or :otel to produce anything.
        field(:profiles_sample_rate, Float).default(0.0)
        # Sentry Logs: forwards everything logged through Ruby's stdlib
        # Logger (i.e. Verse.logger) to Sentry's structured logs.
        field(:enable_logs, [TrueClass, FalseClass]).default(false)
        field(:send_default_pii, [TrueClass, FalseClass]).default(false)
        field(:excluded_exceptions, Array, of: String).default(DEFAULT_EXCLUDED_EXCEPTIONS)

        transform { |schema| Config.new(**schema) }
      end
    end
  end
end
