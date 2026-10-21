# Serves the Angular single-page app, for every shell WEB_UI_SHELLS leaves to
# it. The Dockerfile bakes the production build into public/ — all but its
# index.html, which goes to spa/index.html: in public/ the static file server
# would answer "/" with it before the router could send "/" to the Rails
# landing page. In development there is no build, so this falls back to a
# plain message (run the Angular dev server on :3000 instead).
class SpaController < ActionController::API
  INDEX = Rails.root.join("spa/index.html")

  def index
    if INDEX.file?
      send_file INDEX, type: "text/html", disposition: "inline"
    else
      render json: { service: "fitora-api", spa: "not built in this environment" }, status: :ok
    end
  end
end
