# frozen_string_literal: true

module Verse
  module Sentry
    # Sentry child spans around every Sequel query, for :native tracing mode.
    # (:otel mode gets SQL spans from opentelemetry-instrumentation-pg via
    # verse-otel instead.) Ported from the octave platform's Sentry::Sequel.
    module SequelInstrumentation
      extend self

      def install!
        return if @installed

        @installed = true

        ::Sequel::Database.class_eval do
          previous_method = instance_method(:log_connection_yield)

          define_method(:log_connection_yield) do |sql, conn, args = nil, &block|
            out = nil

            ::Sentry.with_child_span(op: "sequel") do |span|
              span&.set_data(:sql, sql)

              out = previous_method.bind(self).call(sql, conn, args, &block)
            end

            out
          end
        end
      end

      def installed?
        !!@installed
      end
    end
  end
end
