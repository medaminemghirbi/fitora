module Web
  module Superadmin
    # Who publishes Fitora — raison sociale, address, matricule fiscal, contact
    # — as its legal pages name it (Web::LegalHelper).
    class IdentityController < BaseController
      before_action -> { @setting = PlatformSetting.current }

      def show; end

      def update
        return render(:show, status: :unprocessable_content) unless @setting.update(params.require(:identity).permit(*PlatformSetting::IDENTITY_FIELDS))

        flash[:success] = helpers.ngt("common.saved")
        redirect_to "/superadmin/identity", status: :see_other
      end
    end
  end
end
