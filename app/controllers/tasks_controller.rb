class TasksController < ApplicationController
  before_action :require_login
  before_action :set_task, only: [ :update, :destroy ]

  def index
    @tasks = Task.where(user_id: current_user.id)
  end

  def create
    @task = current_user.tasks.new(task_params)
    if @task.save
      TaskDurationEstimateJob.perform_later(@task.id)
    end
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to tasks_path }
    end
  end

  def update
    @old_status = @task.status
    @task.update(task_params)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to tasks_path }
    end
  end

  def destroy
    @task.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to tasks_path }
    end
  end

  private

  def set_task
    @task = Task.find(params[:id])
  end

  def task_params
    params.require(:task).permit(:title, :description, :status)
  end
end
