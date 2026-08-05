# frozen_string_literal: true

require_relative "lib/verse/sentry/version"

Gem::Specification.new do |spec|
  spec.name = "verse-sentry"
  spec.version = Verse::Sentry::VERSION
  spec.authors = ["Ingedata"]

  spec.summary = "Sentry integration for the Verse framework"
  spec.description = "Error tracking and tracing for Verse services: error capture " \
                     "with auth/request context, plus three tracing modes — none " \
                     "(errors only), native (Sentry SDK transactions), or otel " \
                     "(bridge into verse-otel's OpenTelemetry pipeline)."
  spec.homepage = "https://github.com/verse-rb/verse-sentry"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/verse-rb/verse-sentry"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "sentry-ruby", "~> 6"

  # Soft dependencies, add to your service's Gemfile as needed:
  # - `sentry-opentelemetry` + `verse-otel` for `tracing: otel`
  # - `sequel` spans work out of the box in `tracing: native`
end
