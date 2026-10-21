module Api
  module V1
    module Me
      # What a member can read about themselves: which gym they belong to,
      # the subscription they are training on, and whether they have been
      # turning up.
      #
      # Deliberately not ClientSerializer/ContractSerializer — those are the
      # gym's view and carry prices, discounts and payment status. What a
      # member is owed is between them and the desk, not something their app
      # quotes back at them.
      class ProfilesController < BaseController
        before_action :require_client!
        before_action :require_member_app!, only: [ :show ]
        before_action :require_member_company!

        # GET /api/v1/me/profile?company_id=
        def show
          render json: MemberApp.profile(current_client, member_company || member_companies.first, member_companies)
        end

        # PATCH /api/v1/me/profile — { client: { first_name, last_name, phone } }
        #
        # The identity a gym can no longer change once it is shared
        # (Client#identity_shared_beyond?) is the person's own to keep right.
        # The email stays put: it is the login, and changing it would need
        # the new address confirmed first.
        def update
          current_client.update!(params.require(:client).permit(:first_name, :last_name, :phone))
          render json: { client: MemberApp.identity(current_client) }
        end
      end
    end
  end
end
