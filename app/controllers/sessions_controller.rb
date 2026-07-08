class SessionsController < ApplicationController
  def new
    redirect_to tasks_path if logged_in?
  end

  def create
    user = User.find_by(email: params[:email])
    if user&.authenticate(params[:password])
      login(user)
      redirect_to tasks_path, notice: "Welcome back!"
    else
      flash.now[:alert] = "Invalid email or password"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    logout
    redirect_to login_path, notice: "Logged out"
  end
end