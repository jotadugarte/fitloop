# frozen_string_literal: true

class AddDecorationsJsonToDerivedPieces < ActiveRecord::Migration[8.1]
  def change
    add_column :derived_pieces, :decorations_json, :jsonb, null: false, default: []
  end
end
