# frozen_string_literal: true

RSpec.describe Verse::Sentry::Config do
  subject(:result) { described_class::Schema.validate(input) }

  context "with an empty config" do
    let(:input) { {} }

    it "applies safe defaults" do
      expect(result).to be_success

      config = result.value
      expect(config.dsn).to eq ""
      expect(config.tracing).to eq :none
      expect(config.traces_sample_rate).to eq 0.1
      expect(config.profiles_sample_rate).to eq 0.0
      expect(config.send_default_pii).to be false
      expect(config.excluded_exceptions).to include(
        "Verse::Error::NotFound",
        "Verse::Error::ValidationFailed",
        "Verse::Error::Unauthorized"
      )
    end
  end

  context "with a full config" do
    let(:input) do
      {
        dsn: TEST_DSN,
        tracing: :otel,
        traces_sample_rate: 0.5,
        excluded_exceptions: ["MyApp::Ignored"]
      }
    end

    it "keeps the provided values" do
      expect(result).to be_success

      config = result.value
      expect(config.dsn).to eq TEST_DSN
      expect(config.tracing).to eq :otel
      expect(config.traces_sample_rate).to eq 0.5
      expect(config.excluded_exceptions).to eq ["MyApp::Ignored"]
    end
  end

  context "with an invalid tracing mode" do
    let(:input) { { tracing: :jaeger } }

    it "fails validation" do
      expect(result).not_to be_success
      expect(result.errors).to have_key(:tracing)
    end
  end
end
