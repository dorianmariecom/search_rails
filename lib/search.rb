# frozen_string_literal: true

module Search
  # {
  #   id: { field: -> { arel_table[:id] }, type: :bigint },
  #   name: { field: -> { arel_table[:name] }, type: :string },
  #   ...
  # }
  attr_accessor :search_fields

  scope :search, lambda do |q: "", params: {}, fields: search_fields&.keys|
    return all unless search_fields.is_a?(Hash)
    return all unless fields.is_an?(Array)

    fields = fields.map(&:to_s)

    ::Query.evaluate(q.to_s).reduce(all) do |query_scope, parsed|
      key = parsed.is_a?(Hash) ? parsed[:key].to_s.presence_in(fields) : nil
      operator = parsed.is_a?(Hash) ? parsed[:operator] : nil
      value = parsed.is_a?(Hash) ? parsed[:value] : nil

      if key.blank? || operator.blank? || value.blank?
        query_scope.where(
          search_fields.map do |_, search_field|
            type = search_field.fetch(:type, :string)

            if type == :bigint

            search_cast_field(search_field).matches("%#{parsed}%", nil, true)
          end.reduce(&:or)
        )
      elsif key
      end
    end
  end

  def search_cast_field(field, as: :text)
    Arel::Nodes::NamedFunction.new(
      "CAST",
      [
        Arel::Nodes::As.new(
          field,
          Arel::Nodes::SqlLiteral.new(as)
        ),
      ]
    )
  end
end
