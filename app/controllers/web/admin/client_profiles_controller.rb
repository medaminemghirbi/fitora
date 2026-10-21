module Web
  module Admin
    # One member's file (ClientProfileComponent): the banner, the desk's
    # actions, the health file, what happened, their subscriptions — read
    # from what GET /api/v1/clients/:id answers (Clients::Profile.payload,
    # round-tripped through JSON as the Angular page receives it), and each
    # write through the rule its API endpoint applies, behind the same
    # capability, answered with the API's message (K-04).
    class ClientProfilesController < BaseController
      before_action -> { require_capability(:clients) }, only: :show
      before_action -> { refuse_without(:clients) }, except: %i[show sell book sessions]
      before_action -> { refuse_without(:contracts) }, only: :sell
      before_action -> { refuse_without(:bookings) }, only: :book
      before_action -> { refuse unless current_user.admin? }, only: :destroy
      before_action :set_client

      rescue_from ActiveRecord::RecordInvalid, with: ->(invalid) { render_messages(I18n.with_locale(:en) { invalid.record.errors.full_messages }) }
      rescue_from ApplicationRecord::Refused, with: ->(refusal) { render_messages([ refusal.message ]) }

      def show
        return render(:missing) if @client.nil?

        @profile = JSON.parse(Clients::Profile.payload(@client, current_company).to_json).deep_symbolize_keys
        @plans = JSON.parse(CatalogueListing.plans(current_company).map { |p| ContractTypeSerializer.new(p).as_json }.to_json).map(&:deep_symbolize_keys)
        @activities = CatalogueListing.activities(current_company).map { |a| ActivitySerializer.new(a).as_json }
        render partial: "web/admin/client_profiles/body", locals: { p: @profile } if params[:fragment].present?
      end

      # PATCH (JSON) — the health file, as PATCH /api/v1/clients/:id.
      def update
        attributes = params.require(:client).permit(*Client::IDENTITY_FIELDS, :notes, :active, *Membership::PROFILE_FIELDS)
        membership = attributes.slice(:notes, :active, *Membership::PROFILE_FIELDS).to_h.symbolize_keys
        Clients::Profile.update(@client, company: current_company, by: current_user, person: attributes.slice(*Client::IDENTITY_FIELDS).to_h, membership: membership)
        head :no_content
      rescue Clients::Profile::Refusal => e
        render json: { error: e.code, message: e.message, errors: e.errors }, status: :unprocessable_content
      end

      # POST …/invite — as POST /api/v1/clients/:id/invite.
      def invite
        return render(json: { error: "member_app_not_included", message: "The member app comes with Fitora Pro." }, status: :forbidden) unless current_company.member_app?

        Clients::Profile.invite(@client, company: current_company, by: current_user)
        head :accepted
      rescue Clients::Profile::Refusal => e
        render json: { error: e.code, message: e.message, errors: e.errors }, status: :unprocessable_content
      end

      # DELETE — the admin's alone, as DELETE /api/v1/clients/:id.
      def destroy
        name = @client.full_name
        Clients::Profile.remove(@client, company: current_company, by: current_user)
        flash[:success] = helpers.ngt("clients.removed", name: name)
        head :no_content
      end

      # POST …/contracts — a subscription sold, as POST /api/v1/contracts.
      def sell
        Contracts::Actions.sell(@client, company: current_company, by: current_user, params: params)
        head :created
      rescue Contracts::Actions::NotFound => e
        render json: { error: e.message }, status: :not_found
      end

      # POST …/bookings — a seat booked for them, as POST /api/v1/bookings.
      def book
        session = current_company.sessions.find_by(id: params[:session_id])
        return render(json: { error: "Session not found" }, status: :not_found) if session.nil?
        return refuse unless BookingPolicy.new(current_user, Booking.new(session_id: session.id)).create?

        truthy = ->(v) { ActiveModel::Type::Boolean.new.cast(v) || false }
        session.book!(@client, drop_in: truthy.call(params[:drop_in]), trial: truthy.call(params[:trial]))
        head :created
      end

      # GET …/sessions?activity_id=&date= — the booking dialog's sessions, as
      # GET /api/v1/sessions?activity_id&date&status=scheduled lists them
      # (its first page).
      def sessions
        scope = current_company.sessions
        scope = scope.where(coach_id: current_staff_member.coach_id) if current_staff_member&.coach?
        scope = scope.where(activity_id: params[:activity_id], status: :scheduled).for_date(Date.parse(params[:date]))
                     .includes(:activity, :company, :coach, :space).order(:starts_at).limit(20).to_a
        counts = SessionSerializer.confirmed_counts(scope)
        sessions = scope.map { |s| SessionSerializer.new(s, confirmed_count: counts.fetch(s.id, 0)).as_json }
        render partial: "web/admin/client_profiles/session_options", formats: [ :html ], locals: { sessions: sessions }
      rescue Date::Error
        head :bad_request
      end

      private

      # Not one of this salle's members: the page shows its error state, as
      # the Angular page does when GET /clients/:id answers 404; a write gets
      # the API's 404.
      def set_client
        @client = current_company.clients.find_by(id: params[:id])
        return if @client || action_name == "show"

        render json: { error: "Resource not found" }, status: :not_found
      end

      def refuse_without(capability)
        refuse unless capability?(capability)
      end

      def refuse
        render json: { error: "You are not allowed to perform this action" }, status: :forbidden
      end

      def render_messages(messages)
        render json: { error: messages.first || "Validation failed", errors: messages }, status: :unprocessable_content
      end
    end
  end
end
