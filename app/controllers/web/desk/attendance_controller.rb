module Web
  module Desk
    # The check-in panel's requests at the desk — see Web::AttendanceEndpoints.
    class AttendanceController < BaseController
      include Web::AttendanceEndpoints
    end
  end
end
