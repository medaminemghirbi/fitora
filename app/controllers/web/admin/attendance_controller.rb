module Web
  module Admin
    # The check-in panel's requests in the admin shell (the dashboard, the
    # calendar) — see Web::AttendanceEndpoints.
    class AttendanceController < BaseController
      include Web::AttendanceEndpoints
    end
  end
end
