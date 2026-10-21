# The web UI's translation files (config/locales/web/ng/), brought over
# verbatim from the Angular app (frontend/src/assets/i18n) and edited here
# now. Stored under the `ng` key so they can never collide with Rails' own
# translations. Read through Web::Translations (the `ngt` helper), which
# looks them up and interpolates them the way ngx-translate does.
dir = File.join(__dir__, "ng")
%w[fr en ar].to_h do |locale|
  [ locale.to_sym, { ng: JSON.parse(File.read(File.join(dir, "#{locale}.json"))) } ]
end
