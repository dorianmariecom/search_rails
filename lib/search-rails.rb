# frozen_string_literal: true

require "active_support/all"
require "active_record"
require "query-ruby"
require "zeitwerk"
require "chronic"

loader = Zeitwerk::Loader.for_gem(warn_on_extra_files: false)
loader.ignore("#{__dir__}/search-rails.rb")
loader.setup

class Object
  alias is_an? is_a?
end
