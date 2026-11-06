module Web
  # A login with no salle to work in: nothing it can do opens one (a superadmin
  # opens accounts), so the page says who can, and offers the way out.
  class NoSallesController < BaseController
    layout "web/auth"

    before_action :go_home_unless_salle_less

    def show; end

    private

    def go_home_unless_salle_less
      return sign_in_first unless current_user
      go_home unless home_path == web_no_salle_path
    end
  end
end
