Rails.application.config.to_prepare do
  MissionControl::Jobs::ApplicationController.class_eval do
    skip_before_action :authenticate_by_http_basic, raise: false

    # Alternatywnie możesz nadpisać metodę authenticate_by_http_basic
    def authenticate_by_http_basic
      true
    end
  end
end
