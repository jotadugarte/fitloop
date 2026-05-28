class Cart < ApplicationRecord
  belongs_to :nesting_run, optional: true
  belongs_to :user, optional: true
end
