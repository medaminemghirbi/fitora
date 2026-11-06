module Web
  # The documents drawn beside a settings form (settings-preview).
  module SettingsHelper
    PREVIEW_FIELDS = %i[name address city phone email tax_id signatory_name contract_terms].freeze

    def settings_preview_values(company)
      company.slice(*PREVIEW_FIELDS)
    end

    # One printed line, from the fields it prints: as the page first shows it,
    # and with what settings-preview needs to redraw it.
    def settings_doc_line(company, *fields, prefix: "", join: " ", fallback: nil)
      text = fields.map { |field| company[field] }.compact_blank.join(join).presence || (fallback && company[fallback].presence)
      tag.span(text && "#{prefix}#{text}", hidden: text.nil?,
                                           data: { preview_line: fields.join(" "), preview_prefix: prefix, preview_join: join, preview_fallback: fallback })
    end

    # The clauses a contract prints, once a gym has written its own.
    def settings_doc_terms(company)
      company[:contract_terms].to_s.split(/\r?\n/).map { |line| line.strip.sub(/\A\d+[.)]\s*/, "") }.compact_blank
    end
  end
end
