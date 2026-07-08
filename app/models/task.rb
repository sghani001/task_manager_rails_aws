class Task < ApplicationRecord
  belongs_to :user

  validates :title, presence: true
  validates :status, presence: true, inclusion: { in: %w[todo in_progress completed] }

  broadcasts_to ->(task) { "tasks_#{task.user_id}" }, inserts_by: :prepend
end
