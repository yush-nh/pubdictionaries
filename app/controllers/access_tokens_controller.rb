class AccessTokensController < ApplicationController
  before_action :authenticate_user!

  def create
    current_user.create_access_token!(token: SecureRandom.hex(16))

    redirect_back fallback_location: root_path, notice: "Access token was successfully created."
  end
end
