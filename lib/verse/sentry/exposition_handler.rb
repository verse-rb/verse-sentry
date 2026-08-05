# frozen_string_literal: true

module Verse
  module Sentry
    # Enriches the Sentry scope with auth and request context for every
    # exposition invocation (HTTP endpoint or event subscriber) and captures
    # exceptions — including subscriber errors that Verse's event-bus hook
    # swallows after logging. Ported from the octave platform's ExpoHandler.
    #
    # In :native tracing mode it also starts a Sentry transaction per
    # exposition; in :otel mode spans come from verse-otel instead.
    class ExpositionHandler < Verse::Exposition::Handler
      PRIMITIVES = [String, Symbol, Integer, Float, TrueClass, FalseClass, NilClass].freeze

      # rubocop:disable Lint/RescueException
      def call
        return call_next unless ::Sentry.initialized?

        expo = exposition
        name = "#{expo.class.name}##{expo.current_action}"

        ::Sentry.with_scope do |scope|
          enrich_scope(scope, expo, name)

          begin
            traced(name) { call_next }
          rescue Exception => e
            # config.excluded_exceptions filters business 4xx errors; the SDK
            # marks captured exceptions, so a rack-level middleware won't
            # report them a second time.
            ::Sentry.capture_exception(e)
            raise
          end
        end
      end
      # rubocop:enable Lint/RescueException

      private

      def traced(name)
        return yield unless Verse::Sentry.tracing_mode == :native

        transaction = ::Sentry.start_transaction(name: name, op: "verse.exposition")
        ::Sentry.get_current_scope.set_span(transaction) if transaction

        begin
          yield
        ensure
          transaction&.finish
        end
      end

      def enrich_scope(scope, expo, name)
        scope.set_transaction_name(name)

        metadata = expo.auth_context&.metadata || {}

        scope.set_context("Account Metadata", ensure_primitive(metadata))
        scope.set_context(
          "Exposition",
          {
            class: expo.class.name,
            hook: expo.hook.class.name,
            action: expo.current_action,
            params: expo.respond_to?(:params) ? ensure_primitive(expo.params&.to_h) : nil,
            raw_params: expo.respond_to?(:unsafe_params) ? ensure_primitive(expo.unsafe_params&.to_h) : nil
          }.compact
        )

        role = expo.auth_context&.role
        scope.set_tag(:role, role) if role

        user_id = metadata[:id]
        scope.set_user(id: user_id) if user_id

        return unless defined?(Verse::Http::Exposition::Hook) && expo.hook.is_a?(Verse::Http::Exposition::Hook)

        scope.set_rack_env(expo.env) if expo.respond_to?(:env)

        http_method = expo.hook.http_method.to_s.upcase
        scope.set_tag(:http_path, [http_method, expo.hook.path].join("|"))
      end

      # Sentry contexts must contain only JSON-serializable values: keep
      # primitives, walk arrays/hashes, and inspect everything else.
      def ensure_primitive(object)
        case object
        when Hash
          object.to_h { |k, v| [k.to_s, ensure_primitive(v)] }
        when Array
          object.map { |x| ensure_primitive(x) }
        else
          PRIMITIVES.include?(object.class) ? object : object.inspect
        end
      end
    end
  end
end
