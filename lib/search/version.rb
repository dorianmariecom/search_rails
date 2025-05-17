# frozen_string_literal: true

require_relative "../search"

Search::Version =
  Gem::Version.new(File.read(File.expand_path("../../VERSION", __dir__)))
