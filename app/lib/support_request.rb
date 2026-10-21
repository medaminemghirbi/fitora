# A gym writing to Fitora (a problem report, or a plan request with a phone
# number): the ticket, its attachments and the audit trail — and Fitora
# answering it. Shared by POST /api/v1/support_tickets, PATCH
# /api/v1/superadmin/support_tickets/:id/resolve and the web UI's support
# pages.
module SupportRequest
  # Returns the ticket, saved or carrying its errors.
  def self.open(company:, user:, subject:, message:, kind: nil, contact_phone: nil, attachments: nil)
    ticket = company.support_tickets.new(
      subject: subject, message: message, created_by: user,
      kind: SupportTicket.kinds.key?(kind.to_s) ? kind : :general,
      contact_phone: contact_phone
    )
    ticket.attachments.attach(attachments) if attachments.present?

    if ticket.save
      AuditLog.record!(
        company: company, user: user, action: "support_ticket.created",
        auditable: ticket, metadata: { subject: ticket.subject, kind: ticket.kind }
      )
    end
    ticket
  end

  # A superadmin closing the ticket.
  def self.resolve(ticket, by:)
    ticket.update!(status: :resolved)
    AuditLog.record!(
      company: ticket.company, user: by, action: "support_ticket.resolved",
      auditable: ticket, metadata: { subject: ticket.subject }
    )
    ticket
  end
end
