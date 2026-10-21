module Web
  # Every pre-migration URL of a salle shell (/admin/<page>…, /desk/<page>…,
  # /coach/<page>…) → the same page in the login's current salle, query
  # string kept (MIGRATION_AUDIT §8.3), plus the redirects the Angular router
  # already had for older paths.
  class LegacyController < BaseController
    # Old paths the Angular router redirects (app.routes.ts); "" is each
    # shell's default child.
    RENAMED = {
      "admin" => {
        "" => "dashboard",
        "getting-started" => "onboarding",
        "contracts/plans" => "catalogue",
        "contracts/activities" => "catalogue",
        "data-exchange" => "settings/data-exchange",
        "coaches" => "team",
        "staff" => "team",
        "modules" => "subscription"
      },
      "desk" => { "" => "dashboard" },
      "coach" => { "" => "today" }
    }.freeze

    def show
      return sign_in_first unless current_user

      company = current_user.current_company
      return go_home if company.nil? || current_client

      shell = params[:shell].to_s
      page = params[:path].to_s
      page = RENAMED.fetch(shell).fetch(page, page)
      query = request.query_string.presence
      redirect_to "/#{shell}/#{company.id}/#{page}#{"?#{query}" if query}"
    end
  end
end
