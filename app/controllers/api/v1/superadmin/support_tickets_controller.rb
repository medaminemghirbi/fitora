module Api
  module V1
    module Superadmin
      # Cross-company support inbox — every problem report an admin filed
      # from the "Contact" tab, reviewed here rather than per-company (unlike
      # module pre-orders, these are time-sensitive enough to need one list).
      class SupportTicketsController < BaseController
        include ServesAttachments
        before_action :require_superadmin!
        before_action :set_ticket, only: [ :resolve, :attachment ]

        # GET /api/v1/superadmin/support_tickets?status=open
        def index
          tickets = SupportTicket.includes(:company, :created_by).recent
          tickets = tickets.where(status: params[:status]) if params[:status].present?

          render json: {
            support_tickets: paginate(tickets).map { |t| SuperadminSupportTicketSerializer.new(t).as_json },
            meta: pagination_meta(tickets)
          }
        end

        # PATCH /api/v1/superadmin/support_tickets/:id/resolve
        def resolve
          SupportRequest.resolve(@ticket, by: current_user)
          render json: { support_ticket: SuperadminSupportTicketSerializer.new(@ticket).as_json }
        end

        # GET /api/v1/superadmin/support_tickets/:id/attachments/:attachment_id
        def attachment
          file = @ticket.attachments.find(params[:attachment_id])
          redirect_to_attachment(file)
        end

        private

        def set_ticket
          @ticket = SupportTicket.find(params[:id])
        end
      end
    end
  end
end
