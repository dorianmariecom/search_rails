# frozen_string_literal: true

require "rails/all"
require "query-ruby"
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem(warn_on_extra_files: false)
loader.ignore("#{__dir__}/search-rails.rb")
loader.setup

class Object
  alias is_an? is_a?
end
