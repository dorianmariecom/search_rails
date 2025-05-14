# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name = "search_rails"
  s.version = File.read("VERSION").strip
  s.summary = "a powerful search for rails"
  s.description = s.summary
  s.authors = ["Dorian Marié"]
  s.email = "dorian@dorianmarie.com"
  s.files = `git ls-files`.lines.map(&:strip)
  s.require_paths = ["lib"]
  s.homepage = "https://github.com/dorianmariecom/search_rails"
  s.license = "MIT"

  s.add_dependency "rails"
  s.add_dependency "query-ruby"
  s.add_dependency "zeitwerk"
  s.add_dependency "chronic"

  s.metadata["rubygems_mfa_required"] = "true"

  s.required_ruby_version = ">= 3.0"
end
