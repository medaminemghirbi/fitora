module Web
  # The Angular app's words, looked up the way ngx-translate looks them up,
  # so a page reads exactly what its Angular twin reads:
  #
  # - the key in the current language, then in French (the app's
  #   setDefaultLang), then the key itself — ngx-translate shows the key when
  #   nothing matches, and so does this;
  # - {{ name }} placeholders filled from the params; one with no param is
  #   left as written, as ngx-translate's default parser leaves it.
  #
  # The strings live in config/locales/web/ng/*.json (copies of the Angular
  # files), loaded under I18n's `ng` key by config/locales/web/ng.rb.
  module Translations
    FALLBACK = :fr
    # ngx-translate's TranslateDefaultParser#templateMatcher.
    PLACEHOLDER = /{{\s?([^{}\s]*)\s?}}/

    def self.translate(key, params = {}, locale: I18n.locale)
      value = lookup(key, locale)
      value = lookup(key, FALLBACK) unless value.is_a?(String)
      return key.to_s unless value.is_a?(String)

      interpolate(value, params)
    end

    def self.lookup(key, locale)
      I18n.t("ng.#{key}", locale: locale, default: nil)
    end

    def self.interpolate(value, params)
      return value if params.blank?

      params = params.to_h.stringify_keys
      value.gsub(PLACEHOLDER) { params.key?($1) && !params[$1].nil? ? params[$1].to_s : $& }
    end
  end
end
