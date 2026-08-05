# frozen_string_literal: true

require "verse/core"
require "sentry-ruby"

require_relative "sentry/version"
require_relative "sentry/config"
require_relative "sentry/exposition_handler"
require_relative "sentry/sequel_instrumentation"
require_relative "sentry/plugin"

module Verse
  # Sentry integration for Verse. Error capture with auth/request context,
  # plus three tracing modes:
  #
  # - :none   — errors only
  # - :native — Sentry SDK transactions per exposition + Sequel query spans
  # - :otel   — bridge verse-otel's OpenTelemetry spans into Sentry
  #
  # NOTE: within this namespace the Sentry SDK must be referenced as
  # `::Sentry` — a bare `Sentry` resolves to `Verse::Sentry`.
  module Sentry
    extend self

    # Set by the plugin; read by the exposition handler.
    attr_accessor :tracing_mode

    # Test seam: clears all module state.
    def reset!
      @tracing_mode = nil
    end
  end
end
