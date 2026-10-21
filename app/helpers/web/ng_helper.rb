module Web
  # The Angular app's pipes and small presentational components, as helpers:
  # each answers exactly what its Angular twin answers, so a page built from
  # them reads and measures the same (MIGRATION_AUDIT §2.3).
  module NgHelper
    # The `translate` pipe (ngx-translate) — see Web::Translations.
    def ngt(key, **params)
      Web::Translations.translate(key, params, locale: I18n.locale)
    end

    # The `date` pipe (DatePipe) with one of the app's patterns, in the gym's
    # time zone. nil prints nothing, as the pipe does.
    def ng_date(value, pattern)
      return "" if value.blank?

      Web::DateFormat.angular(value.in_time_zone, pattern, locale: I18n.locale)
    end

    # A Date#toLocaleDateString / Intl.DateTimeFormat call the app makes.
    def ng_intl_date(value, format_name)
      return "" if value.blank?

      Web::DateFormat.intl(value.in_time_zone, format_name, locale: I18n.locale)
    end

    # MoneyPipe: "120 DT", "40.5 €" — two decimals, ".00" dropped, then the
    # currency's symbol. nil is "—".
    def ng_money(value, currency)
      return "—" if value.nil?

      amount = value.is_a?(String) ? Float(value, exception: false) : value.to_f
      formatted = amount&.finite? ? ng_to_fixed(amount, 2).delete_suffix(".00") : value.to_s
      "#{formatted} #{Web::Currency.symbol(currency)}"
    end

    # Number#toFixed: rounds the exact binary value, an exact tie away from
    # zero (0.125 → "0.13"), where format("%.2f") would round it to even.
    def ng_to_fixed(number, digits)
      format("%.#{digits}f", number.to_r.round(digits, half: :up))
    end

    # AvatarComponent#initials: the first letter of the first two words,
    # upper-cased; "?" for no name.
    def ng_initials(name)
      parts = name.to_s.strip.split(/[[:space:]]+/).reject(&:empty?)
      return "?" if parts.empty?

      parts.first(2).map { |part| part[0].upcase }.join
    end

    # AvatarComponent's size styles: the font is 40 % of the size, computed
    # in floating point exactly as the template's `size * 0.4` is.
    def ng_avatar_style(size)
      "width: #{size}px; height: #{size}px; font-size: #{ng_css_number(size * 0.4)}px;"
    end

    # A number as JavaScript prints it into a style (13.6, 14, 12.8).
    def ng_css_number(number)
      number == number.to_i ? number.to_i.to_s : number.to_s
    end

    # The icon classes the support page gives a file by its type, after "bi"
    # ([class.bi-file-earmark-image]… bindings).
    def support_file_icon(content_type)
      type = content_type.to_s
      icon = if type.start_with?("image/") then "bi-file-earmark-image"
      elsif type.start_with?("video/") then "bi-file-earmark-play"
      elsif type == "application/pdf" then "bi-file-earmark-pdf"
      end
      icon ? " #{icon}" : ""
    end

    # [innerHTML] bound to markup the app trusts (bypassSecurityTrustHtml):
    # the backend's own SVG, inserted as it is.
    def ng_inner_html(html)
      html.to_s.html_safe # rubocop:disable Rails/OutputSafety
    end

    # HighlightPipe: every case-insensitive occurrence of the term, wrapped
    # in <mark class="fx-hl">. Text and term are escaped first, so the only
    # markup in the result is the pipe's own.
    def ng_highlight(text, term)
      source = ERB::Util.html_escape(text.to_s)
      needle = term.to_s.strip
      return source if needle.empty?

      pattern = Regexp.new(Regexp.escape(ERB::Util.html_escape(needle)), Regexp::IGNORECASE)
      source.to_str.gsub(pattern) { |match| %(<mark class="fx-hl">#{match}</mark>) }.html_safe
    end
  end
end
