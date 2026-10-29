module Api
  module V1
    class ClientsController < BaseController
      before_action :require_company!
      before_action -> { require_capability!(:clients) }
      # Taking someone off the gym's books (and, for their last gym, erasing
      # them) is the admin's decision.
      before_action :require_admin!, only: :destroy
      before_action :set_client, only: [ :show, :update, :invite, :destroy ]
      # This controller's errors also carry `message`, refused or invalid alike.
      rescue_from ApplicationRecord::Refused, with: ->(refusal) { render_error(refusal.message) }
      rescue_from ActiveRecord::RecordInvalid, with: ->(invalid) {
        messages = invalid.record.errors.full_messages
        render_error(messages.first, errors: messages)
      }

      # Between two invitations to the same person, so a double click does
      # not send two emails.
      INVITE_COOLDOWN = Clients::Profile::INVITE_COOLDOWN

      # GET /api/v1/clients?search=&status=&page=
      # status: active | inactive | contract_active | contract_expired | no_contract
      #
      # Beyond the search box, the list narrows on the plan someone holds, the
      # activity it covers, their gender and when they joined, and it orders on
      # a whitelisted column — see Clients::ListQuery, which the web UI's
      # members page reads too.
      def index
        list = Clients::ListQuery.new(current_company, params)

        if params[:format] == "csv"
          # The whole member file leaving the building: admin only.
          return render_forbidden unless current_user.admin?

          send_data list.csv, filename: "clients-#{Date.current}.csv"
        else
          page = paginate(list.scope).to_a
          visits = list.last_visits_for(page)
          context = ClientSerializer.page_context(page, current_company)

          render json: {
            clients: page.map { |c|
              ClientSerializer.new(
                c, company: current_company, last_visit_at: visits[c.id],
                membership: context[:memberships][c.id], current_contract: context[:current_contracts][c.id]
              ).as_json
            },
            meta: pagination_meta(list.scope),
            counts: list.counts
          }
        end
      end

      # GET /api/v1/clients/:id
      def show
        render json: Clients::Profile.payload(@client, current_company)
      end

      # POST /api/v1/clients — adds someone to THIS gym, optionally selling
      # them a plan and taking the money in the same transaction
      # (Clients::Enrolment, shared with the web UI's new-member wizard).
      #
      # An email Fitora already knows, for someone this gym does not train,
      # adds no one: 202 with the request the person was emailed
      # (MembershipRequest), holding only what was sent here.
      def create
        return render_forbidden if subscription_params.present? && !capability?(:contracts)

        result = Clients::Enrolment.call(
          company: current_company, user: current_user,
          person: person_params, membership: membership_params, subscription: subscription_params
        )
        if result.pending?
          return render json: { membership_request: MembershipRequestSerializer.new(result.request).as_json }, status: :accepted
        end

        render json: {
          client: ClientSerializer.new(result.client, company: current_company).as_json,
          contract: result.contract && ContractSerializer.new(result.contract).as_json,
          payment: result.payment && PaymentSerializer.new(result.payment).as_json
        }, status: :created
      end

      # PATCH /api/v1/clients/:id
      #
      # What the gym wrote about the person lands on its own membership. The
      # person's name, email and phone are the gym's to change only while the
      # gym is the only one that knows them (Client#identity_shared_beyond?);
      # after that it can fill in what is blank, and anything else is refused
      # rather than silently dropped. No password is ever accepted here — see
      # #invite.
      def update
        Clients::Profile.update(@client, company: current_company, by: current_user, person: person_params.to_h, membership: membership_params)
        render json: { client: ClientSerializer.new(@client, company: current_company).as_json }
      rescue Clients::Profile::Refusal => e
        render json: { error: e.code, message: e.message, errors: e.errors }, status: :unprocessable_content
      end

      # POST /api/v1/clients/:id/invite — switches the member's own app on by
      # emailing them a link to choose their password. The gym never picks,
      # sees or resets it; a member who forgets it uses "forgot password"
      # like anyone else.
      def invite
        unless current_company.member_app?
          return render json: {
            error: "member_app_not_included",
            message: "The member app comes with Fitora Pro."
          }, status: :forbidden
        end

        Clients::Profile.invite(@client, company: current_company, by: current_user)
        render json: { client: ClientSerializer.new(@client, company: current_company).as_json }, status: :accepted
      rescue Clients::Profile::Refusal => e
        render_error(e.message, code: e.code == e.message ? nil : e.code)
      end

      # DELETE /api/v1/clients/:id — see Client#remove_from!.
      def destroy
        Clients::Profile.remove(@client, company: current_company, by: current_user)
        head :no_content
      end

      private

      def set_client
        @client = current_company.clients.find(params[:id])
      end

      def subscription_params
        return {} if params[:subscription].blank?

        params.require(:subscription).permit(
          :contract_type_id, :activity_id, :pack_id, :starts_on, :discount,
          :collect_payment, :payment_method, :payment_notes
        )
      end

      def membership_params
        client_params.slice(:notes, :active, *Membership::PROFILE_FIELDS).to_h.symbolize_keys
      end

      def person_params
        client_params.slice(*Client::IDENTITY_FIELDS)
      end

      def render_error(message, code: nil, errors: [ message ])
        render json: { error: code || message, message: message, errors: errors }, status: :unprocessable_content
      end

      def client_params
        params.require(:client).permit(
          :first_name, :last_name, :email, :phone, :date_of_birth, :gender,
          :address, :emergency_contact_name, :emergency_contact_phone, :notes, :active,
          :health_notes, :waiver_signed_on
        )
      end
    end
  end
end
