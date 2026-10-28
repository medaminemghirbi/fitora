module Web
  # What the legal pages print about the company that publishes Fitora —
  # read from Superadmin → Billing, so the pages and the invoices never
  # disagree — and the day the current text applies from.
  module LegalHelper
    # Change it with the text.
    UPDATED_ON = Date.new(2026, 10, 28)

    def legal_publisher
      issuer.legal_name.presence || "Fitora"
    end

    # "Fitora SARL, 12 rue …, Tunis — matricule fiscal …", with whatever is
    # filled in.
    def legal_identity(tax_label:)
      parts = [ legal_publisher, [ issuer.address, issuer.city ].compact_blank.join(", ").presence ]
      parts << "#{tax_label} #{issuer.tax_id}" if issuer.tax_id.present?
      parts.compact.join(" — ")
    end

    def legal_contact
      issuer.email.presence || "contact@fitora.io"
    end
  end
end
