module Api
  module V1
    # Settings → Application mobile: the salle's two keys and their QR codes,
    # and a way to replace either. A Pro tool (paid Pro only).
    class MobileAppController < BaseController
      before_action :require_company!
      before_action :require_admin!
      before_action :require_pro!

      # GET /api/v1/mobile_app
      def show
        render json: MobileAppKeys.as_json(current_company)
      end

      # POST /api/v1/mobile_app/regenerate { audience: "member" | "coach" }
      def regenerate
        audience = params[:audience].to_s
        return render_errors("Unknown audience") unless MobileAppKeys::AUDIENCES.include?(audience)

        MobileAppKeys.regenerate!(current_company, audience: audience, by: current_user)
        render json: MobileAppKeys.as_json(current_company)
      end
    end
  end
end
