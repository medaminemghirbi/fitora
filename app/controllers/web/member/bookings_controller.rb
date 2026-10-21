module Web
  module Member
    # The member's bookings (MemberBookingsComponent) — upcoming, or past with
    # ?when=past (kept in the URL, M-05) — as GET /api/v1/me/bookings lists
    # them, across every gym whose app they can open; and booking a seat
    # (MemberScheduleComponent#book) or giving one back, as
    # POST /api/v1/me/bookings and …/cancel do.
    class BookingsController < BaseController
      before_action -> { render_refusal("member_app_not_included", status: :forbidden) if member_companies.empty? }, only: %i[create cancel]

      def index
        @when = params[:when] == "past" ? "past" : "upcoming"
        @bookings = member_companies.any? ? JSON.parse(MemberApp.bookings(current_client, member_companies.map(&:id), upcoming: @when == "upcoming").to_json).map(&:deep_symbolize_keys) : nil
        render partial: "web/member/bookings/list", locals: { bookings: @bookings, timing: @when } if params[:fragment].present?
      end

      def create
        session = ::Session.where(company_id: member_companies.map(&:id)).find_by(id: params[:session_id]) # rubocop:disable Fitora/UnscopedTenantQuery
        return render_refusal("Session not found", status: :not_found) if session.nil?

        booking = session.book!(current_client, by: :member)
        # The schedule redraws the session's row from it (B-12).
        if request.format.html?
          row = JSON.parse(PublicSessionSerializer.new(session.reload, current_client: current_client).as_json.to_json).deep_symbolize_keys
          return render(partial: "web/member/schedule/slot", locals: { s: row }, status: :created)
        end

        render json: { booking: BookingSerializer.new(booking).as_json, waitlisted: booking.waitlisted? }, status: :created
      rescue ApplicationRecord::Refused => e
        render_refusal(e.message)
      rescue ActiveRecord::RecordInvalid => e
        render_refusal(I18n.with_locale(:en) { e.record.errors.full_messages })
      end

      def cancel
        booking = current_client.bookings.joins(:session).where(sessions: { company_id: member_companies.map(&:id) }).find_by(id: params[:id])
        return render_refusal("Resource not found", status: :not_found) if booking.nil?

        booking.cancel!(by: :member)
        render json: { booking: BookingSerializer.new(booking.reload).as_json }
      rescue ApplicationRecord::Refused => e
        render_refusal(e.message)
      end
    end
  end
end
