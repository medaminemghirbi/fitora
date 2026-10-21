module Web
  # The public landing page (LandingComponent), at "/". Nothing on it is
  # read from the database: its figures and mocks are illustrative, as in
  # Angular.
  class LandingController < BaseController
    layout "web/auth"

    # guestGuard: a signed-in visitor goes to their home instead.
    before_action :go_home_if_signed_in

    def show; end

    private

    def go_home_if_signed_in
      go_home if signed_in?
    end
  end
end
