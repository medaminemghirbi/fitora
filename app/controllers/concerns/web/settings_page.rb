module Web
  # A page that lives in Settings: drawn inside the settings' own menu, with the
  # main menu down to its icons (layouts/web/admin_settings). Settings' own
  # sections do, and so do the pages a gym sets up once and rarely reopens,
  # which keep their own addresses and guards: the plateau, the plans, the
  # team and the salles.
  module SettingsPage
    extend ActiveSupport::Concern

    included do
      layout "web/admin_settings"
      helper_method :sections, :current_settings_path, :needs_attention?
    end

    class_methods do
      # Which entry of the menu this controller's pages light up.
      def settings_section(path)
        private define_method(:current_settings_path) { path }
      end
    end

    private

    def sections
      @sections ||= Web::SettingsSections.new(user: current_user, permissions: bootstrap[:permissions], features: bootstrap[:features])
    end

    # The menu's dot: what the gym's own documents still lack.
    def needs_attention?(item)
      item.path == "contracts" && !current_company.signature.attached?
    end
  end
end
