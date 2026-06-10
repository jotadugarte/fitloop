# frozen_string_literal: true

class CreateFeedbacks < ActiveRecord::Migration[8.1]
  def change
    create_table :feedbacks do |t|
      t.references :user, null: true, foreign_key: true
      t.string :email
      t.string :feedback_type, null: false
      t.text :message, null: false
      t.string :source_url
      t.string :status, null: false, default: "pending"
      t.jsonb :guest_metadata, null: false, default: {}

      t.timestamps
    end

    add_index :feedbacks, :status
    add_index :feedbacks, :feedback_type
  end
end
