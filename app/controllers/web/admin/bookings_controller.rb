module Web
  module Admin
    # The salle's bookings (AdminBookingsComponent) — routable, deliberately
    # not in the nav. Listed by Bookings::ListQuery, cancelled through
    # Bookings::Actions after BookingPolicy, as /api/v1/bookings does.
    class BookingsController < BaseController
      PER_PAGE = 20

      before_action -> { require_capability(:bookings) }, only: :index
      before_action :set_booking, only: :cancel
      # A booking that cannot be cancelled: the API's 422 and its message
      # (ApplicationController#render_refused), which the page toasts — not
      # a 500.
      rescue_from ApplicationRecord::Refused, with: ->(refusal) { render json: { error: refusal.message }, status: :unprocessable_content }

      STATUSES = [
        [ "", "common.all", "var(--color-primary)" ],
        [ "confirmed", "bookings.status_confirmed", "var(--color-success)" ],
        [ "completed", "bookings.status_completed", "var(--color-info)" ],
        [ "no_show", "bookings.status_no_show", "var(--color-warning)" ],
        [ "cancelled", "bookings.status_cancelled", "var(--color-danger)" ]
      ].freeze
      helper_method :booking_statuses

      def index
        list = Bookings::ListQuery.new(current_company, params, staff_member: current_staff_member)
        @filters = list.params
        @page = [ params[:page].to_i, 1 ].max
        scope = list.scope
        @bookings = scope.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).map { |b| BookingSerializer.new(b).as_json }
        total = scope.count
        @meta = { page: @page, per_page: PER_PAGE, total: total, total_pages: (total.to_f / PER_PAGE).ceil }
        @counts = list.counts
        respond_to do |format|
          format.html
          format.turbo_stream
        end
      end

      def cancel
        return head(:forbidden) unless BookingPolicy.new(current_user, @booking).cancel?

        Bookings::Actions.cancel(@booking, by: current_user)
        head :no_content
      end

      private

      def set_booking
        @booking = Bookings::ListQuery.new(current_company, {}).company_scope.find(params[:id])
      end

      def booking_statuses
        STATUSES
      end
    end
  end
end
