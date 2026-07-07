class Task < ApplicationRecord
  belongs_to :user
  broadcasts_to ->(task) { "tasks_#{task.user_id}" }, inserts_by: :prepend
end
