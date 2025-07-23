# frozen_string_literal: true

module Search
  extend ActiveSupport::Concern

  class_methods do
    # def self.search_fields
    #   {
    #     id: { node: -> { arel_table[:id] }, type: :integer },
    #     name: { node: -> { arel_table[:name] }, type: :string },
    #     input: { node: -> { arel_table[:input] }, type: :string },
    #     updated_at: { node: -> { arel_table[:updated_at] }, type: :datetime },
    #     created_at: { node: -> { arel_table[:created_at] }, type: :datetime },
    #   }
    # end
    def search_fields
      {}
    end

    def _search_extract_node(node, keys = [])
      keys << node[:key]

      if node[:value].is_a?(Hash)
        _search_extract_node(node[:value], keys)
      else
        { **node, key: keys.join(":") }
      end
    end

    def _search_cast(node:, type: "text")
      Arel::Nodes::NamedFunction.new("cast", [node.as(type)])
    end

    def _search_cast_boolean(value)
      if value.is_a?(Range)
        first = _search_cast_boolean(value.first)
        last = _search_cast_boolean(value.last)

        value.exclude_end? ? first...last : first..last
      else
        ActiveModel::Type::Boolean.new.cast(value)
      end
    end

    def _search_cast_integer(value)
      if value.is_a?(Range)
        first = _search_cast_integer(value.first)
        last = _search_cast_integer(value.last)

        value.exclude_end? ? first...last : first..last
      else
        ActiveModel::Type::Integer.new.cast(value)
      end
    end

    def _search_cast_string(value)
      if value.is_a?(Range)
        first = _search_cast_string(value.first)
        last = _search_cast_string(value.last)

        value.exclude_end? ? first...last : first..last
      else
        ActiveModel::Type::String.new.cast(value)
      end
    end

    def _search_cast_datetime(value)
      if value.is_a?(Range)
        first = _search_cast_datetime(value.first)
        last = _search_cast_datetime(value.last)
        first = first.first if first.is_a?(Range)
        last = last.last if last.is_a?(Range)
        value.exclude_end? ? first...last : first..last
      else
        Chronic.time_class = Time.zone
        Chronic.parse(_search_cast_string(value), guess: false)
      end
    end
  end

  included do
    # q:
    #   ""
    #   "dorian"
    #   "given_name:dor"
    #   "age>30 given_name:dor family_name:mar programmer"
    # params:
    #   {
    #     verified: true,
    #     primary: false,
    #     id: 1,
    #     given_name: "Dorian",
    #   }
    # fields:
    #   [:id, :name, :input]
    scope :search,
          lambda { |q: "", fields: search_fields&.keys|
            raise ArgumentError unless search_fields.is_an?(Hash)
            raise ArgumentError unless fields.is_an?(Array)

            fields = fields.map(&:to_s)
            q = q.to_s

            where(
              id:
                _search_joins(
                  scope:
                    _search_parsed(
                      parsed: ::Query.evaluate(q),
                      scope: all,
                      fields: fields
                    ),
                  fields: fields
                )
            )
          }

    scope :_search_joins,
          lambda { |scope:, fields:|
            fields = fields.map(&:to_s)

            relations =
              fields.filter_map do |field|
                search_fields.fetch(field.to_sym)[:relation]
              end

            relations.reduce(scope) do |scope_with_relations, relation|
              relation.call(scope_with_relations)
            end
          }

    scope :_search_parsed,
          lambda { |parsed:, scope:, fields:|
            if parsed.is_a?(String)
              scope._search_fields(q: parsed, fields: fields)
            elsif parsed.is_a?(Hash)
              if parsed.key?(:left)
                if parsed[:operator] == "or"
                  scope.where(
                    id:
                      _search_parsed(
                        parsed: parsed[:left],
                        scope: scope,
                        fields: fields
                      )
                  ).or(
                    scope.where(
                      id:
                        _search_parsed(
                          parsed: parsed[:right],
                          scope: scope,
                          fields: fields
                        )
                    )
                  )
                elsif parsed[:operator] == "and"
                  scope.where(
                    id:
                      _search_parsed(
                        parsed: parsed[:left],
                        scope: scope,
                        fields: fields
                      )
                  ).where(
                    id:
                      _search_parsed(
                        parsed: parsed[:right],
                        scope: scope,
                        fields: fields
                      )
                  )
                end
              elsif parsed.key?(:right)
                scope.where.not(
                  id:
                    _search_parsed(
                      parsed: parsed[:right],
                      scope: scope,
                      fields: fields
                    )
                )
              elsif parsed.key?(:key)
                parsed = _search_extract_node(parsed)
                key = parsed[:key].to_s.presence_in(fields)
                operator = parsed[:operator]
                value = parsed[:value]

                if key.blank?
                  scope.none
                else
                  scope._search_field(
                    key: key,
                    operator: operator,
                    value: value
                  )
                end
              else
                raise ArgumentError
              end
            else
              raise ArgumentError
            end
          }

    # q:
    #   "dorian"
    #   "1"
    # fields: [:id, :given_name, :family_name]
    scope :_search_fields,
          lambda { |q: "", fields: search_fields&.keys|
            raise ArgumentError unless search_fields.is_an?(Hash)
            raise ArgumentError unless fields.is_an?(Array)

            fields = fields.map(&:to_s)
            q = q.to_s

            where(
              fields
                .map do |field|
                  field = search_fields.fetch(field.to_sym)
                  node = field[:node].call
                  casted_field = _search_cast(node: node, type: :text)
                  casted_field.matches("%#{q}%", nil, false)
                end
                .reduce(&:or)
            )
          }

    # key: input, name, id, created_at, updated_at, verified, admin, ...
    # operator: :, =, >, ~, <, >=, ...
    # value: "pomodoro", 123, true, false
    scope :_search_field,
          lambda { |key:, value:, operator: ":", fields: search_fields&.keys|
            raise ArgumentError unless search_fields.is_an?(Hash)
            raise ArgumentError unless fields.is_an?(Array)

            fields = fields.map(&:to_s)
            key = key.to_s.presence_in(fields)

            raise ArgumentError if key.blank?
            raise ArgumentError if operator.blank?

            field = search_fields.fetch(key.to_sym)

            case operator
            when ":"
              _search_colon(field: field, value: value)
            when "^"
              _search_starts(field: field, value: value)
            when "$"
              _search_ends(field: field, value: value)
            when ">="
              _search_greater_or_equal(field: field, value: value)
            when "<="
              _search_lesser_or_equal(field: field, value: value)
            when ">"
              _search_greater(field: field, value: value)
            when "<"
              _search_lesser(field: field, value: value)
            when "~"
              _search_matches(field: field, value: value)
            when "="
              _search_equal(field: field, value: value)
            when "!:"
              where.not(id: _search_colon(field: field, value: value))
            when "!!"
              where.not(id: _search_colon(field: field, value: value))
            when "!^"
              where.not(id: _search_starts(field: field, value: value))
            when "!$"
              where.not(id: _search_ends(field: field, value: value))
            when "!>="
              where.not(
                id: _search_greater_or_equal(field: field, value: value)
              )
            when "!<="
              where.not(id: _search_lesser_or_equal(field: field, value: value))
            when "!>"
              where.not(id: _search_greater(field: field, value: value))
            when "!<"
              where.not(id: _search_lesser(field: field, value: value))
            when "!="
              where.not(id: _search_equal(field: field, value: value))
            else
              raise ArgumentError
            end
          }

    # id:1, name:dorian, verified:true, created_at:today
    scope :_search_colon,
          lambda { |field:, value:|
            node = field[:node].call

            case field[:type]
            when :integer
              _search_integer_eq(node: node, value: value)
            when :string
              _search_string_matches(node: node, value: value)
            when :datetime
              _search_datetime_eq(node: node, value: value)
            when :boolean
              _search_boolean_eq(node: node, value: value)
            else
              raise ArgumentError
            end
          }

    scope :_search_matches,
          lambda { |field:, value:|
            node = field[:node].call

            case field[:type]
            when :integer
              _search_integer_eq(node: node, value: value)
            when :string
              _search_string_matches(node: node, value: value)
            when :datetime
              _search_datetime_eq(node: node, value: value)
            when :boolean
              _search_boolean_eq(node: node, value: value)
            else
              raise ArgumentError
            end
          }

    scope :_search_ends,
          lambda { |field:, value:|
            node = field[:node].call

            case field[:type]
            when :integer
              _search_integer_eq(node: node, value: value)
            when :string
              _search_string_ends(node: node, value: value)
            when :datetime
              _search_datetime_eq(node: node, value: value)
            when :boolean
              _search_boolean_eq(node: node, value: value)
            else
              raise ArgumentError
            end
          }

    scope :_search_starts,
          lambda { |field:, value:|
            node = field[:node].call

            case field[:type]
            when :integer
              _search_integer_eq(node: node, value: value)
            when :string
              _search_string_starts(node: node, value: value)
            when :datetime
              _search_datetime_eq(node: node, value: value)
            when :boolean
              _search_boolean_eq(node: node, value: value)
            else
              raise ArgumentError
            end
          }

    scope :_search_equal,
          lambda { |field:, value:|
            node = field[:node].call

            case field[:type]
            when :integer
              _search_integer_eq(node: node, value: value)
            when :string
              _search_string_eq(node: node, value: value)
            when :datetime
              _search_datetime_eq(node: node, value: value)
            when :boolean
              _search_boolean_eq(node: node, value: value)
            else
              raise ArgumentError
            end
          }

    scope :_search_lesser,
          lambda { |field:, value:|
            node = field[:node].call

            case field[:type]
            when :integer
              _search_integer_lt(node: node, value: value)
            when :string
              _search_string_lt(node: node, value: value)
            when :datetime
              _search_datetime_lt(node: node, value: value)
            when :boolean
              none
            else
              raise ArgumentError
            end
          }

    scope :_search_lesser_or_equal,
          lambda { |field:, value:|
            node = field[:node].call

            case field[:type]
            when :integer
              _search_integer_lteq(node: node, value: value)
            when :string
              _search_string_lteq(node: node, value: value)
            when :datetime
              _search_datetime_lteq(node: node, value: value)
            when :boolean
              _search_boolean_eq(node: node, value: value)
            else
              raise ArgumentError
            end
          }

    scope :_search_greater,
          lambda { |field:, value:|
            node = field[:node].call

            case field[:type]
            when :integer
              _search_integer_gt(node: node, value: value)
            when :string
              _search_string_gt(node: node, value: value)
            when :datetime
              _search_datetime_gt(node: node, value: value)
            when :boolean
              none
            else
              raise ArgumentError
            end
          }

    scope :_search_greater_or_equal,
          lambda { |field:, value:|
            node = field[:node].call

            case field[:type]
            when :integer
              _search_integer_gteq(node: node, value: value)
            when :string
              _search_string_gteq(node: node, value: value)
            when :datetime
              _search_datetime_gteq(node: node, value: value)
            when :boolean
              _search_boolean_eq(node: node, value: value)
            else
              raise ArgumentError
            end
          }

    scope :_search_integer_eq,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :bigint)
            value = _search_cast_integer(value)

            if value.is_a?(Range)
              if value.exclude_end?
                where(node.gteq(value.first).and(node.lt(value.last)))
              else
                where(node.gteq(value.first).and(node.lteq(value.last)))
              end
            else
              where(node.eq(value))
            end
          }

    scope :_search_datetime_eq,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :timestamp)
            value = _search_cast_datetime(value)

            if value.is_a?(Range)
              if value.exclude_end?
                where(node.gteq(value.first).and(node.lt(value.last)))
              else
                where(node.gteq(value.first).and(node.lteq(value.last)))
              end
            else
              where(node.eq(value))
            end
          }

    scope :_search_string_eq,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :text)
            value = _search_cast_string(value)

            if value.is_a?(Range)
              if value.exclude_end?
                where(node.gteq(value.first).and(node.lt(value.last)))
              else
                where(node.gteq(value.first).and(node.lteq(value.last)))
              end
            else
              where(node.eq(value))
            end
          }

    scope :_search_boolean_eq,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :boolean)
            value = _search_cast_boolean(value)

            if value.is_a?(Range)
              if value.exclude_end?
                where(node.eq(value.first).and(node.not_eq(value.last)))
              else
                where(node.eq(value.first)).or(where(node.eq(value.last)))
              end
            else
              where(node.eq(value))
            end
          }

    scope :_search_integer_lt,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :bigint)
            value = _search_cast_integer(value)
            value = value.first if value.is_a?(Range)

            where(node.lt(value))
          }

    scope :_search_datetime_lt,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :timestamp)
            value = _search_cast_datetime(value)
            value = value.first if value.is_a?(Range)

            where(node.lt(value))
          }

    scope :_search_string_lt,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :text)
            value = _search_cast_string(value)
            value = value.first if value.is_a?(Range)

            where(node.lt(value))
          }

    scope :_search_integer_lteq,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :bigint)
            value = _search_cast_integer(value)
            value = value.first if value.is_a?(Range)

            where(node.lteq(value))
          }

    scope :_search_datetime_lteq,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :timestamp)
            value = _search_cast_datetime(value)
            value = value.first if value.is_a?(Range)

            where(node.lteq(value))
          }

    scope :_search_string_lteq,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :text)
            value = _search_cast_string(value)
            value = value.first if value.is_a?(Range)

            where(node.lteq(value))
          }

    scope :_search_integer_gt,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :bigint)
            value = _search_cast_integer(value)
            value = value.last if value.is_a?(Range)

            where(node.gt(value))
          }

    scope :_search_datetime_gt,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :timestamp)
            value = _search_cast_datetime(value)
            value = value.last if value.is_a?(Range)

            where(node.gt(value))
          }

    scope :_search_string_gt,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :text)
            value = _search_cast_string(value)
            value = value.last if value.is_a?(Range)

            where(node.gt(value))
          }

    scope :_search_integer_gteq,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :bigint)
            value = _search_cast_integer(value)
            value = value.last if value.is_a?(Range)

            where(node.gteq(value))
          }

    scope :_search_datetime_gteq,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :timestamp)
            value = _search_cast_datetime(value)
            value = value.last if value.is_a?(Range)

            where(node.gteq(value))
          }

    scope :_search_string_gteq,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :text)
            value = _search_cast_string(value)
            value = value.last if value.is_a?(Range)

            where(node.gteq(value))
          }

    scope :_search_string_matches,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :text)
            value = _search_cast_string(value)

            if value.is_a?(Range)
              if value.exclude_end?
                where(node.gteq(value.first).and(node.lt(value.last)))
              else
                where(node.gteq(value.first).and(node.lteq(value.last)))
              end
            else
              where(node.matches("%#{value}%", nil, false))
            end
          }

    scope :_search_string_ends,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :text)
            value = _search_cast_string(value)

            if value.is_a?(Range)
              if value.exclude_end?
                where(node.gteq(value.first).and(node.lt(value.last)))
              else
                where(node.gteq(value.first).and(node.lteq(value.last)))
              end
            else
              where(node.matches("%#{value}", nil, false))
            end
          }

    scope :_search_string_starts,
          lambda { |node:, value:|
            node = _search_cast(node: node, type: :text)
            value = _search_cast_string(value)

            if value.is_a?(Range)
              if value.exclude_end?
                where(node.gteq(value.first).and(node.lt(value.last)))
              else
                where(node.gteq(value.first).and(node.lteq(value.last)))
              end
            else
              where(node.matches("#{value}%", nil, false))
            end
          }
  end
end
