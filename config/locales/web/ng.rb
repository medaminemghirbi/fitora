# The Angular app's translation files (frontend/src/assets/i18n), copied
# verbatim into config/locales/web/ng/ by test/parity/sync-from-angular.mjs,
# stored under the `ng` key so they can never collide with Rails' own
# translations. Read through Web::Translations (the `ngt` helper), which
# looks them up and interpolates them the way ngx-translate does.
dir = File.join(__dir__, "ng")
%w[fr en ar].to_h do |locale|
  [ locale.to_sym, { ng: JSON.parse(File.read(File.join(dir, "#{locale}.json"))) } ]
end
