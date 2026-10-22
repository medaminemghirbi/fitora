# Be sure to restart your server when you modify this file.

# What the web UI's pages may load. Everything is served from this origin
# except Google Fonts; styles stay 'unsafe-inline' because the views use
# style attributes and FullCalendar and Turbo inject <style> elements.
# Images and media may come from https: (a coach's photo URL, Active Storage
# on S3). Scripts: this origin only — the views' inline <script>s are JSON
# data blocks, which never run.
#
# Report-only until CSP_ENFORCE is set, so a page this list forgot is
# reported, not broken. CSP_REPORT_URI sends the reports somewhere (Sentry's
# security endpoint, for one); without it they only reach the browser console.
#
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  # Browser errors are sent to the Sentry project's host, when there is one
  # (lib/error_reporting.js): its origin, without the DSN's key.
  sentry = config.x.sentry_browser_dsn && URI.parse(config.x.sentry_browser_dsn)
  sentry_origin = sentry && "#{sentry.scheme}://#{sentry.host}#{":#{sentry.port}" unless sentry.port == sentry.default_port}"

  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self
    policy.style_src :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.font_src :self, :data, "https://fonts.gstatic.com"
    policy.img_src :self, :data, :blob, :https
    policy.media_src :self, :blob, :https
    policy.connect_src :self, *sentry_origin
    policy.object_src :none
    policy.base_uri :self
    policy.form_action :self
    policy.frame_ancestors :none
    policy.report_uri ENV["CSP_REPORT_URI"] if ENV["CSP_REPORT_URI"].present?
  end

  config.content_security_policy_report_only = ENV["CSP_ENFORCE"].blank?
end
