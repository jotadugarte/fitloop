# frozen_string_literal: true

class AddSplitProposalPlanResult < ActiveRecord::Migration[8.1]
  def change
    change_table :split_proposals, bulk: true do |t|
      t.boolean :feasible, null: false, default: true
      t.string :plan_reason
    end
  end
end
