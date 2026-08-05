# frozen_string_literal: true

# Minimal stand-in for the Sequel gem: only the seam the instrumentation
# patches. Defined before install! so class_eval targets it.
module Sequel
  class Database
    def log_connection_yield(sql, _conn, _args = nil)
      block_given? ? yield : sql
    end
  end
end

RSpec.describe Verse::Sentry::SequelInstrumentation do
  before(:all) { described_class.install! }

  let(:db) { Sequel::Database.new }

  it "installs only once" do
    expect(described_class.installed?).to be true
    expect { described_class.install! }.not_to change { described_class.installed? }
  end

  it "passes the query result through when Sentry is not active" do
    expect(db.log_connection_yield("SELECT 1", nil) { :rows }).to eq :rows
  end

  context "with an active native transaction" do
    before { init_sentry(tracing: :native) }

    it "records a sequel child span with the sql attached" do
      transaction = ::Sentry.start_transaction(name: "spec", op: "test")
      ::Sentry.get_current_scope.set_span(transaction)

      result = db.log_connection_yield("SELECT * FROM users", nil) { :rows }
      transaction.finish

      expect(result).to eq :rows

      spans = sentry_transactions.first.spans
      sequel_span = spans.find { |s| s[:op] == "sequel" }
      expect(sequel_span).not_to be_nil
      expect(sequel_span[:data][:sql] || sequel_span[:data]["sql"]).to eq "SELECT * FROM users"
    end
  end
end
