# Configure Mission Control Jobs
# For development, we'll disable authentication
# In production, you should enable HTTP Basic Auth or integrate with your auth system

if Rails.env.development?
  # Disable authentication for local development
  Rails.application.config.after_initialize do
    MissionControl::Jobs.base_controller_class = "ActionController::Base"
  end
else
  # Enable HTTP Basic Auth for production
  MissionControl::Jobs.http_basic_auth_user = ENV.fetch("MISSION_CONTROL_USERNAME")
  MissionControl::Jobs.http_basic_auth_password = ENV.fetch("MISSION_CONTROL_PASSWORD")
end
