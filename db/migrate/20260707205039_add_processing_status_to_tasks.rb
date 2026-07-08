class AddProcessingStatusToTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :processing_status, :string
  end
end
