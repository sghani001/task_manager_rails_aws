class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      t.string :title
      t.text :description
      t.string :status
      t.integer :user_id
      t.string :duration_estimate

      t.timestamps
    end
  end
end
