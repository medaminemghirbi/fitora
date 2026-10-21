module Bookings
  # Cancelling a booking and reminding its member, each with its audit
  # trail — for /api/v1/bookings and the web UI alike. Who may do either is
  # BookingPolicy's question, asked by the caller first.
  module Actions
    def self.cancel(booking, by:)
      booking.cancel!
      AuditLog.record!(
        company: booking.session.company, user: by, action: "booking.cancelled",
        auditable: booking, metadata: { client: booking.client.full_name, activity: booking.session.activity.name }
      )
      booking
    end

    def self.remind(booking, by:)
      booking.send_reminder!
      AuditLog.record!(
        company: booking.session.company, user: by, action: "booking.reminder_sent",
        auditable: booking, metadata: { client: booking.client.full_name }
      )
      booking
    end
  end
end
