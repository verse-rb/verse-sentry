# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  skip do |file|
    file.filename !~ /lib/
  end
end

# Never let the OTel SDK go looking for an OTLP exporter during specs.
ENV["OTEL_TRACES_EXPORTER"] = "none"

require "pry"
require "bundler"
Bundler.require

require "verse/sentry"
require "verse/otel"
require "sentry/test_helper"

TEST_DSN = "https://12345abcdef@o424242.ingest.us.sentry.io/8888888"

module SentrySpecHelpers
  # Initialize the real SDK, then swap in the dummy transport so nothing
  # leaves the process. Events are inspected via sentry_events and friends.
  def init_sentry(tracing: :none, traces_sample_rate: 1.0)
    plugin = Verse::Sentry::Plugin.new(
      "sentry",
      { dsn: TEST_DSN, tracing:, traces_sample_rate: },
      {},
      Logger.new(IO::NULL)
    )
    plugin.on_init
    setup_sentry_test

    plugin
  end

  def sentry_transactions
    sentry_transport.events.select { |e| e.is_a?(::Sentry::TransactionEvent) }
  end

  # Guarded on defined?: specs that hide the Verse::Otel constant are still
  # inside the stub when this runs as an after hook.
  def clean_exposition_handlers
    ours = [Verse::Sentry::ExpositionHandler]
    ours << Verse::Otel::ExpositionHandler if defined?(Verse::Otel)

    Verse::Exposition::Base.handlers.reject! do |entry|
      entry.is_a?(Array) && ours.include?(entry.first)
    end
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.include ::Sentry::TestHelper
  config.include SentrySpecHelpers

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:suite) do
    Verse.logger = Logger.new(IO::NULL)
  end

  config.after(:each) do
    teardown_sentry_test if ::Sentry.initialized?
    ::Sentry.instance_variable_set(:@main_hub, nil)
    clean_exposition_handlers
    Verse::Sentry.reset!
    Verse::Otel.reset! if defined?(Verse::Otel)
  end
end
