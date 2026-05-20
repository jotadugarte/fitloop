# frozen_string_literal: true

class RemovePinDigestFromProjects < ActiveRecord::Migration[8.1]
  def change
    remove_column :projects, :pin_digest, :string
    change_column_default :projects, :ephemeral, from: false, to: true
  end
end
