module Web
  # The language switch (D6): remembers the choice and reloads the page the
  # person was on — same path, same query string, so the salle and every
  # filter come back as they were.
  class LocalesController < BaseController
    def update
      remember_locale(params[:locale])
      redirect_to safe_return_to, status: :see_other
    end

    private

    # Only a path on this site: never an open redirect.
    def safe_return_to
      path = params[:return_to].to_s
      path.start_with?("/") && !path.start_with?("//") ? path : "/connexion"
    end
  end
end
