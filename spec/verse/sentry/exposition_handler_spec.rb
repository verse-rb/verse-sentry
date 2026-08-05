# frozen_string_literal: true

class FakeSentryHook; end

# Minimal stand-in for verse-http, which is not a dependency of this gem:
# only the seam enrich_scope branches on. Defined at load time so the
# `defined?(Verse::Http::Exposition::Hook)` guard sees it.
module Verse
  module Http
    module Exposition
      class Hook
        attr_reader :http_method, :path

        def initialize(http_method: :get, path: "/users/:id")
          @http_method = http_method
          @path = path
        end
      end
    end
  end
end

class FakeSentryExposition
  attr_reader :current_action, :hook, :auth_context, :params

  def initialize(action: :show, metadata: {}, role: nil, params: nil, hook: nil)
    @current_action = action
    @hook = hook || FakeSentryHook.new
    @auth_context = Struct.new(:metadata, :role).new(metadata, role)
    @params = params
  end
end

# Separate class because enrich_scope guards on `respond_to?(:env)` — the
# non-HTTP fake must not answer to it.
class FakeHttpExposition < FakeSentryExposition
  attr_reader :env

  def initialize(env:, **kwargs)
    super(hook: Verse::Http::Exposition::Hook.new, **kwargs)
    @env = env
  end
end

RSpec.describe Verse::Sentry::ExpositionHandler do
  let(:exposition) do
    FakeSentryExposition.new(
      metadata: { id: "user-1", organization_id: 42 },
      role: "admin",
      params: { q: "hello", nested: { at: Time.at(0) }, tags: ["ok", Time.at(0)] }
    )
  end

  def run_handler(expo = exposition, &block)
    inner = Verse::Exposition::Handler.new(block, expo)
    described_class.new(inner, expo).call
  end

  def exposition_context_of(event)
    event.contexts["Exposition"] || event.contexts[:Exposition]
  end

  context "when Sentry is not initialized" do
    it "passes through" do
      expect(run_handler { :done }).to eq :done
    end
  end

  context "when Sentry is initialized" do
    before { init_sentry }

    it "passes the result through" do
      expect(run_handler { :done }).to eq :done
      expect(sentry_events).to be_empty
    end

    it "captures exceptions with the enriched scope and re-raises" do
      expect { run_handler { raise ArgumentError, "boom" } }
        .to raise_error(ArgumentError, "boom")

      expect(sentry_events.size).to eq 1
      event = last_sentry_event

      expect(event.transaction).to eq "FakeSentryExposition#show"
      expect(event.tags[:role]).to eq "admin"
      expect(event.user[:id]).to eq "user-1"

      exposition_context = exposition_context_of(event)
      expect(exposition_context[:action]).to eq :show
      expect(exposition_context[:params]["q"]).to eq "hello"
      # Non-primitive values are stringified for safe serialization.
      expect(exposition_context[:params]["nested"]["at"]).to be_a(String)
      # ...including inside arrays, which are walked element by element.
      expect(exposition_context[:params]["tags"]).to contain_exactly("ok", a_string_matching(/1970/))

      account_context = event.contexts["Account Metadata"] || event.contexts[:"Account Metadata"]
      expect(account_context["organization_id"]).to eq 42
    end

    it "does not report excluded verse business errors" do
      expect { run_handler { raise Verse::Error::NotFound } }
        .to raise_error(Verse::Error::NotFound)

      expect(sentry_events).to be_empty
    end
  end

  context "in native tracing mode" do
    before { init_sentry(tracing: :native) }

    it "records a transaction per exposition" do
      expect(run_handler { :done }).to eq :done

      expect(sentry_transactions.size).to eq 1
      expect(sentry_transactions.first.transaction).to eq "FakeSentryExposition#show"
    end

    it "finishes the transaction even when the call raises" do
      expect { run_handler { raise ArgumentError, "boom" } }
        .to raise_error(ArgumentError, "boom")

      expect(sentry_transactions.size).to eq 1

      error_events = sentry_events.reject { |e| e.is_a?(::Sentry::TransactionEvent) }
      expect(error_events.size).to eq 1
    end
  end

  context "in otel tracing mode" do
    before { init_sentry(tracing: :otel) }

    # Transactions in otel mode come from the bridged OpenTelemetry span
    # processor. The SDK's :otel instrumenter would neuter start_transaction
    # anyway, so assert the handler never reaches for it — that is the part
    # this gem controls.
    it "starts no transaction of its own" do
      expect(::Sentry).not_to receive(:start_transaction)

      expect(run_handler { :done }).to eq :done

      expect(sentry_transactions).to be_empty
    end

    it "still captures exceptions" do
      expect { run_handler { raise ArgumentError, "boom" } }
        .to raise_error(ArgumentError, "boom")

      expect(sentry_events.size).to eq 1
      expect(sentry_transactions).to be_empty
    end
  end

  context "with an HTTP exposition" do
    before { init_sentry }

    let(:http_exposition) do
      FakeHttpExposition.new(
        metadata: { id: "user-1" },
        env: {
          "REQUEST_METHOD" => "GET",
          "PATH_INFO" => "/users/1",
          "QUERY_STRING" => "",
          "rack.url_scheme" => "http",
          "HTTP_HOST" => "example.org",
          "SERVER_NAME" => "example.org",
          "SERVER_PORT" => "80"
        }
      )
    end

    it "tags the route and attaches the rack request" do
      expect { run_handler(http_exposition) { raise ArgumentError, "boom" } }
        .to raise_error(ArgumentError, "boom")

      event = last_sentry_event
      expect(event.tags[:http_path]).to eq "GET|/users/:id"
      expect(event.request.url).to eq "http://example.org/users/1"
      expect(event.request.method).to eq "GET"
    end
  end

  context "with an event-subscriber exposition" do
    before { init_sentry }

    let(:event_exposition) do
      FakeSentryExposition.new(
        action: :on_user_created,
        metadata: { id: "system" },
        hook: Verse::Exposition::Hook::EventBus.new(FakeSentryExposition)
      )
    end

    # Verse's event-bus hook logs subscriber errors itself; capture has to
    # happen here, inside exposition.run, or Sentry never sees them.
    it "captures subscriber errors and re-raises for the event bus" do
      expect { run_handler(event_exposition) { raise ArgumentError, "boom" } }
        .to raise_error(ArgumentError, "boom")

      expect(sentry_events.size).to eq 1
      event = last_sentry_event

      expect(event.transaction).to eq "FakeSentryExposition#on_user_created"
      expect(exposition_context_of(event)[:hook])
        .to eq "Verse::Exposition::Hook::EventBus"
      # The HTTP-only enrichment must stay out of the event path.
      expect(event.tags).not_to have_key(:http_path)
    end
  end
end
