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

  s.add_dependency "chronic", ">= 0.10.2", "< 1"
  s.add_dependency "query-ruby", ">= 2.0.2", "< 3"
  s.add_dependency "rails", ">= 8.1.3.1", "< 9"
  s.add_dependency "zeitwerk", ">= 2.8.3", "< 3"

  s.metadata["rubygems_mfa_required"] = "true"

  s.required_ruby_version = ">= 4.0"
end
