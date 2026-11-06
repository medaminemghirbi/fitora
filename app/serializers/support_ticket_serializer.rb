class SupportTicketSerializer
  def initialize(ticket)
    @ticket = ticket
  end

  def as_json(*)
    {
      id: ticket.id,
      subject: ticket.subject,
      message: ticket.message,
      status: ticket.status,
      created_at: ticket.created_at,
      attachments: attachments_json
    }
  end

  private

  attr_reader :ticket

  def attachments_json
    ticket.attachments.map do |file|
      {
        id: file.id,
        filename: file.filename.to_s,
        content_type: file.content_type,
        byte_size: file.byte_size,
        url: Rails.application.routes.url_helpers.attachment_api_v1_support_ticket_path(ticket, attachment_id: file.id)
      }
    end
  end
end
