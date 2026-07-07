class TaskDurationEstimateJob < ApplicationJob
  queue_as :default

  def perform(task_id)
    task = Task.find(task_id)

    # Simulate slow async work — e.g. calling out to an AWS Lambda,
    # a Textract job, or any other long-running process.
    estimate = SlowEstimationService.call(task.title, task.description)
    task.update!(duration_estimate: estimate)

    # The task already re-broadcasts via broadcasts_to on update — but if you want
    # a more targeted UI change (e.g. flash a "estimate ready" badge), broadcast explicitly:
    Turbo::StreamsChannel.broadcast_replace_to(
      "tasks_#{task.user_id}",
      target: ActionView::RecordIdentifier.dom_id(task),
      partial: "tasks/task",
      locals: { task: task }
    )
  end
end
