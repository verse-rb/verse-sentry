# frozen_string_literal: true

RSpec.describe Verse::Sentry::Plugin do
  let(:logger) { Logger.new(IO::NULL) }

  def make_plugin(config)
    described_class.new("sentry", config, {}, logger)
  end

  def registered_handlers
    Verse::Exposition::Base.handlers.map { |h| h.is_a?(Array) ? h.first : h }
  end

  context "without a DSN" do
    it "disables everything" do
      make_plugin({}).on_init

      expect(::Sentry.initialized?).to be_falsey
      expect(registered_handlers).not_to include(Verse::Sentry::ExpositionHandler)
    end

    it "treats a nil DSN (unset env var in config.yml) as disabled" do
      make_plugin({ dsn: nil }).on_init

      expect(::Sentry.initialized?).to be_falsey
      expect(registered_handlers).not_to include(Verse::Sentry::ExpositionHandler)
    end
  end

  context "with a DSN" do
    around do |example|
      previous = ENV["APP_ENVIRONMENT"]
      ENV["APP_ENVIRONMENT"] = "spec-env"
      example.run
    ensure
      ENV["APP_ENVIRONMENT"] = previous
    end

    it "logs the tracing mode once initialized" do
      expect(logger).to receive(:info) do |&block|
        expect(block.call).to eq "Verse::Sentry enabled (tracing: none, traces: 0.1, logs: false, profiles: 0.0)"
      end

      make_plugin({ dsn: TEST_DSN }).on_init
    end

    it "initializes Sentry with verse defaults" do
      make_plugin({ dsn: TEST_DSN }).on_init

      expect(::Sentry.initialized?).to be true

      config = ::Sentry.configuration
      expect(config.environment).to eq "spec-env"
      expect(config.send_default_pii).to be false
      expect(config.excluded_exceptions).to include("Verse::Error::NotFound")

      expect(registered_handlers.first).to eq Verse::Sentry::ExpositionHandler
      expect(Verse::Sentry.tracing_mode).to eq :none
    end

    it "keeps the SDK instrumenter in :none and :native modes" do
      make_plugin({ dsn: TEST_DSN, tracing: :native, traces_sample_rate: 0.7 }).on_init

      expect(::Sentry.configuration.instrumenter).to eq :sentry
      expect(::Sentry.configuration.traces_sample_rate).to eq 0.7
      expect(Verse::Sentry.tracing_mode).to eq :native
    end
  end

  context "with tracing: otel" do
    it "bridges into the Verse::Otel registry" do
      make_plugin({ dsn: TEST_DSN, tracing: :otel, traces_sample_rate: 0.3 }).on_init

      config = ::Sentry.configuration
      expect(config.instrumenter).to eq :otel
      expect(config.traces_sample_rate).to eq 0.3

      expect(Verse::Otel.span_processors)
        .to include(::Sentry::OpenTelemetry::SpanProcessor.instance)
      expect(Verse::Otel.propagator).to be_a(::Sentry::OpenTelemetry::Propagator)

      # Regression guard: the SDK's own envelope uploads must never be traced.
      expect(Verse::Otel.untraced_hosts).to include("o424242.ingest.us.sentry.io")
    end
  end

  context "with tracing: otel but the optional gems missing" do
    it "raises a pointed error when verse-otel is absent" do
      hide_const("Verse::Otel")

      expect { make_plugin({ dsn: TEST_DSN, tracing: :otel }).on_init }
        .to raise_error(/requires the verse-otel gem/)
    end

    it "raises and tells the user to install sentry-opentelemetry" do
      plugin = make_plugin({ dsn: TEST_DSN, tracing: :otel })
      allow(plugin).to receive(:require).and_call_original
      allow(plugin).to receive(:require).with("sentry-opentelemetry").and_raise(LoadError)

      expect(logger).to receive(:error) do |&block|
        expect(block.call).to match(/add `sentry-opentelemetry` to your Gemfile/)
      end

      expect { plugin.on_init }.to raise_error(LoadError)
    end
  end

  context "with profiling but stackprof missing" do
    it "raises and tells the user to install stackprof" do
      plugin = make_plugin({ dsn: TEST_DSN, tracing: :native, profiles_sample_rate: 0.5 })
      allow(plugin).to receive(:require).and_call_original
      allow(plugin).to receive(:require).with("stackprof").and_raise(LoadError)

      expect(logger).to receive(:error) do |&block|
        expect(block.call).to match(/add `stackprof` to your Gemfile/)
      end

      expect { plugin.on_init }.to raise_error(LoadError)
    end
  end

  describe "HTTP middleware" do
    let(:server) { Class.new { def self.use(middleware); (@used ||= []) << middleware; end } }

    it "installs the capture middleware inner to Verse's ErrorHandler" do
      stub_const("Verse::Http::Server", server)
      expect(server).to receive(:use).with(::Sentry::Rack::CaptureExceptions)

      make_plugin({ dsn: TEST_DSN }).on_init
    end

    it "is skipped when the service has no HTTP server" do
      expect { make_plugin({ dsn: TEST_DSN }).on_init }.not_to raise_error
    end
  end

  context "with an invalid config" do
    it "raises" do
      expect { make_plugin({ tracing: :jaeger }).on_init }
        .to raise_error(/Invalid verse-sentry plugin config/)
    end
  end

  describe "Sentry Logs" do
    it "is off by default" do
      make_plugin({ dsn: TEST_DSN }).on_init

      expect(::Sentry.configuration.enable_logs).to be false
    end

    it "enables structured logs and mirrors the stdlib Logger" do
      make_plugin({ dsn: TEST_DSN, enable_logs: true }).on_init

      expect(::Sentry.configuration.enable_logs).to be true
      expect(::Logger.ancestors).to include(::Sentry::StdLibLogger)
    end
  end

  describe "Sentry Profiles" do
    it "is off by default" do
      make_plugin({ dsn: TEST_DSN, tracing: :otel }).on_init

      expect(::Sentry.configuration.profiles_sample_rate).to eq 0.0
    end

    it "applies the sample rate in otel mode" do
      make_plugin({ dsn: TEST_DSN, tracing: :otel, profiles_sample_rate: 0.5 }).on_init

      expect(::Sentry.configuration.profiles_sample_rate).to eq 0.5
      expect(defined?(StackProf)).to be_truthy
    end

    it "applies the sample rate in native mode" do
      make_plugin({ dsn: TEST_DSN, tracing: :native, profiles_sample_rate: 0.2 }).on_init

      expect(::Sentry.configuration.profiles_sample_rate).to eq 0.2
    end

    it "stays unset when tracing is none (profiles ride on transactions)" do
      make_plugin({ dsn: TEST_DSN, tracing: :none, profiles_sample_rate: 0.5 }).on_init

      expect(::Sentry.configuration.profiles_sample_rate).to be_nil
    end
  end
end
