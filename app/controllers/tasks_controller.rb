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
      flash.now[:notice] = "Task created"
    else
      flash.now[:alert] = @task.errors.full_messages.to_sentence
    end
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to tasks_path }
    end
  end

  def update
    @old_status = @task.status
    if @task.update(task_params)
      flash.now[:notice] = "Task updated"
    else
      flash.now[:alert] = @task.errors.full_messages.to_sentence
    end
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to tasks_path }
    end
  end

  def destroy
    if @task.destroy
      flash.now[:notice] = "Task deleted"
    else
      flash.now[:alert] = "Failed to delete task"
    end
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to tasks_path }
    end
  end

  private

  def set_task
    @task = current_user.tasks.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "Task not found or unauthorized"
    redirect_to tasks_path
    throw :abort
  end

  def task_params
    params.require(:task).permit(:title, :description, :status)
  end
end
