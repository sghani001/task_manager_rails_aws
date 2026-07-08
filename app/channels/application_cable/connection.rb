module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      # For development, use the same demo user as the web app
      # In production, you'd authenticate via cookies/session
      User.find_or_create_by!(email: "demo@example.com") do |user|
        user.password = "password"
      end
    end
  end
end
