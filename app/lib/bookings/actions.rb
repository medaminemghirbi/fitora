module Bookings
  # Cancelling a booking, with its audit trail — for /api/v1/bookings and the
  # web UI alike. Who may is BookingPolicy's question, asked by the caller
  # first.
  module Actions
    def self.cancel(booking, by:)
      booking.cancel!
      AuditLog.record!(
        company: booking.session.company, user: by, action: "booking.cancelled",
        auditable: booking, metadata: { client: booking.client.full_name, activity: booking.session.activity.name }
      )
      booking
    end
  end
end
