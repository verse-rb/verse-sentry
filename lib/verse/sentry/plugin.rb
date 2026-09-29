# frozen_string_literal: true

module Verse
  module Sentry
    # Verse plugin. Declare it in a service's config.yml:
    #
    #   plugins:
    #     - plugin: sentry
    #       config:
    #         dsn: <%= ENV["SENTRY_DSN"] %>
    #         environment: <%= ENV["SENTRY_ENVIRONMENT"] %> # default: APP_ENVIRONMENT
    #         tracing: otel   # none | native | otel
    #         traces_sample_rate: <%= ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", 0.1) %>
    #
    # With `tracing: otel` the otel plugin (verse-otel gem) must also be
    # declared; this plugin then contributes the Sentry bridge (span
    # processor, propagator, and the DSN host as an untraced host) to
    # Verse::Otel's registry during on_init — verse-otel consumes the
    # registry in on_start, so declaration order does not matter.
    #
    # An empty or missing dsn disables everything.
    class Plugin < Verse::Plugin::Base
      # simplecov:disable
      def description
        "Sentry error tracking and tracing for Verse"
      end
      # simplecov:disable

      def on_init
        @config = validate_config

        if @config.dsn.to_s.empty?
          logger.info { "verse-sentry disabled (no DSN configured)" }
          return
        end

        Verse::Sentry.tracing_mode = @config.tracing

        init_sentry!
        install_http_middleware!
        Verse::Exposition::Base.prepend_handler(ExpositionHandler)
        setup_tracing!
        setup_logs!

        logger.info do
          "Verse::Sentry enabled (tracing: #{@config.tracing}, " \
            "traces: #{@config.traces_sample_rate}, "\
            "logs: #{@config.enable_logs}, " \
            "profiles: #{@config.profiles_sample_rate})"
        end
      end

      private

      def init_sentry!
        setup_profiler!

        cfg = @config

        ::Sentry.init do |c|
          c.dsn = cfg.dsn
          c.environment = environment

          c.breadcrumbs_logger = [:sentry_logger, :http_logger]
          c.send_default_pii = cfg.send_default_pii
          c.background_worker_threads = 3

          c.excluded_exceptions += cfg.excluded_exceptions

          c.enable_logs = cfg.enable_logs

          case cfg.tracing
          when :native
            c.traces_sample_rate = cfg.traces_sample_rate
          when :otel
            # Spans are produced by OpenTelemetry (verse-otel) and bridged by
            # the span processor registered in setup_tracing!; the SDK must
            # not start its own transactions.
            c.instrumenter = :otel
            c.traces_sample_rate = cfg.traces_sample_rate
          end

          # Profiles ride on transactions, so they apply to both tracing
          # modes (the otel bridge starts real Sentry transactions, which
          # trigger the profiler).
          c.profiles_sample_rate = cfg.profiles_sample_rate if cfg.tracing != :none
        end
      end

      # Several installs can share a DSN, and the Verse environment names only
      # which config files to load, so an install may report its own name.
      def environment
        name = @config.environment.to_s.strip
        name.empty? ? ENV.fetch("APP_ENVIRONMENT", "development") : name
      end

      # Sentry Logs: mirror everything logged through Ruby's stdlib Logger
      # (Verse.logger included) into Sentry's structured logs. The module
      # guards against recursion on the SDK's own log lines.
      def setup_logs!
        return unless @config.enable_logs
        return if ::Logger.ancestors.include?(::Sentry::StdLibLogger)

        ::Logger.prepend(::Sentry::StdLibLogger)
      end

      # The default Sentry profiler is backed by stackprof, which the SDK
      # does not require by itself. Must load before ::Sentry.init so the
      # SDK sees the dependency as installed.
      def setup_profiler!
        return unless @config.profiles_sample_rate.positive? && @config.tracing != :none

        begin
          require "stackprof"
        rescue LoadError
          logger.error { "Please add `stackprof` to your Gemfile to use Sentry profiling!" }
          raise
        end
      end

      def install_http_middleware!
        return unless defined?(Verse::Http::Server)

        # Added after the middleware declared in the Server class body,
        # therefore inner to Verse's ErrorHandler: sees exceptions before
        # they are swallowed and rendered as HTTP error responses.
        Verse::Http::Server.use ::Sentry::Rack::CaptureExceptions
      end

      def setup_tracing!
        case @config.tracing
        when :otel
          setup_otel_bridge!
        when :native
          SequelInstrumentation.install! if defined?(::Sequel::Database)
        end
      end

      def setup_otel_bridge!
        unless defined?(Verse::Otel)
          raise "verse-sentry `tracing: otel` requires the verse-otel gem — " \
                "add it to your Gemfile and declare the otel plugin in config.yml"
        end

        begin
          require "sentry-opentelemetry"
        rescue LoadError
          logger.error { "Please add `sentry-opentelemetry` to your Gemfile to use `tracing: otel`!" }
          raise
        end

        Verse::Otel.add_span_processor(::Sentry::OpenTelemetry::SpanProcessor.instance)
        Verse::Otel.propagator = ::Sentry::OpenTelemetry::Propagator.new

        # Never trace the SDK's own envelope uploads: the bridge's
        # from_sentry_sdk? filter misses them under the stable HTTP semconv
        # naming, which otherwise floods traces with self-referential POSTs.
        host = ::Sentry.configuration.dsn&.host
        Verse::Otel.untraced_hosts << host if host
      end

      def validate_config
        result = Config::Schema.validate(config)
        return result.value if result.success?

        raise "Invalid verse-sentry plugin config: #{result.errors}"
      end
    end
  end
end
