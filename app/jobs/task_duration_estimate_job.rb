class TaskDurationEstimateJob < ApplicationJob
  queue_as :default

  def perform(task_id)
    task = Task.find(task_id)

    # Mark as processing and broadcast immediately
    task.update!(processing_status: "estimating")
    broadcast_task(task)  # Card shows "estimating..." spinner immediately

    # Simulate slow async work — e.g. calling out to an AWS Lambda,
    # a Textract job, or any other long-running process.
    estimate = SlowEstimationService.call(task.title, task.description)

    # Mark as done with the estimate and broadcast
    task.update!(duration_estimate: estimate, processing_status: "done")
    broadcast_task(task)  # Card updates to show the estimate
  end

  private

  def broadcast_task(task)
    Turbo::StreamsChannel.broadcast_replace_to(
      "tasks_#{task.user_id}",
      target: ActionView::RecordIdentifier.dom_id(task),
      partial: "tasks/task",
      locals: { task: task }
    )
  end
end
