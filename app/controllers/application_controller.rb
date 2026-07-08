class ApplicationController < ActionController::Base
  helper_method :current_user, :logged_in?

  allow_browser versions: :modern
  stale_when_importmap_changes

  private

  def current_user
    @_current_user ||= User.find_by(id: session[:user_id])
  end

  def logged_in?
    current_user.present?
  end

  def require_login
    redirect_to login_path unless logged_in?
  end

  def login(user)
    session[:user_id] = user.id
  end

  def logout
    session[:user_id] = nil
    @_current_user = nil
  end
end
