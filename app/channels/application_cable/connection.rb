module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      if (user_id = request.session["user_id"])
        User.find_by(id: user_id) || reject_unauthorized_connection
      elsif Rails.env.development?
        email = ENV.fetch("SEED_USER_EMAIL", "demo@example.com")
        password = ENV.fetch("SEED_USER_PASSWORD", "password")
        User.find_or_create_by!(email: email) { |u| u.password = password }
      else
        reject_unauthorized_connection
      end
    end
  end
end
