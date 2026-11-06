module Api
  module V1
    # A problem report with optional file/video attachments, reviewed by a
    # Fitora superadmin from a cross-company inbox
    # (Web::Superadmin::SupportController).
    class SupportTicketsController < BaseController
      include ServesAttachments
      before_action :require_admin!
      before_action :set_ticket, only: [ :attachment ]

      # GET /api/v1/support_tickets
      def index
        tickets = current_company.support_tickets.recent.limit(SupportTicket::LIST_LIMIT)
        render json: { support_tickets: tickets.map { |t| SupportTicketSerializer.new(t).as_json } }
      end

      # POST /api/v1/support_tickets (multipart/form-data — attachments[] are uploads)
      def create
        ticket = SupportRequest.open(
          company: current_company, user: current_user, subject: params[:subject], message: params[:message],
          attachments: params[:attachments]
        )

        if ticket.persisted?
          render json: { support_ticket: SupportTicketSerializer.new(ticket).as_json }, status: :created
        else
          render_errors(ticket)
        end
      end

      def attachment
        file = @ticket.attachments.find(params[:attachment_id])
        redirect_to_attachment(file)
      end

      private

      def set_ticket
        @ticket = current_company.support_tickets.find(params[:id])
      end
    end
  end
end
