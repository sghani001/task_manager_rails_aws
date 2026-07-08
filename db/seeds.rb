email = ENV.fetch("SEED_USER_EMAIL", "demo@example.com")
password = ENV.fetch("SEED_USER_PASSWORD", "password")

demo_user = User.find_or_create_by!(email: email) do |user|
  user.password = password
end

tasks = [
  { title: "Design the landing page", description: "Create wireframes and high-fidelity mockups for the new landing page.", status: "todo" },
  { title: "Set up CI/CD pipeline", description: "Configure GitHub Actions for automated testing and deployment.", status: "todo" },
  { title: "Write API documentation", description: "Document all REST endpoints with request/response examples.", status: "in_progress", duration_estimate: "~3 hours" },
  { title: "Refactor user authentication", description: "Extract auth logic into a separate service object for testability.", status: "in_progress", duration_estimate: "~5 hours" },
  { title: "Fix pagination bug on search results", description: "Page parameter is being ignored when search query is present.", status: "completed", duration_estimate: "~1 hour" },
  { title: "Upgrade dependencies", description: "Bump Rails to 8.1 and update all outdated gems.", status: "completed", duration_estimate: "~2 hours" }
]

tasks.each do |attrs|
  demo_user.tasks.find_or_create_by!(title: attrs[:title]) do |task|
    task.description = attrs[:description]
    task.status = attrs[:status]
    task.duration_estimate = attrs[:duration_estimate]
    task.processing_status = "done"
  end
end
