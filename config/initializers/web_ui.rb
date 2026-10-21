# The web UI's templates (app/views/web, app/views/layouts/web) compile the way
# Angular compiles its own — whitespace and style scoping — so the HTML they
# produce matches the Angular app's. See Web::AngularTemplate. Every other
# .erb template is handed to the ordinary ERB handler unchanged.
#
# The handler is a stable object that resolves Web::AngularTemplate on each
# compile, so the class itself stays reloadable in development.
module WebUiErbHandler
  def self.call(template, source) = Web::AngularTemplate.call(template, source)
  def self.handles_encoding? = true
end

ActiveSupport.on_load(:action_view) do
  ActionView::Template.register_template_handler :erb, WebUiErbHandler
end

# The Angular translations are read by config/locales/web/ng.rb, so Rails'
# own reloader, which watches the locale load path, never sees the JSON copies
# change: a running server kept printing a new key as the key. In
# development, a change to any of them reloads the translations.
if Rails.env.development?
  ng_translations = ActiveSupport::FileUpdateChecker.new(Dir[Rails.root.join("config/locales/web/ng/*.json")]) { I18n.reload! }
  Rails.application.reloaders << ng_translations
  Rails.application.reloader.to_run { ng_translations.execute_if_updated }
end
