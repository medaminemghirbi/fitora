module Api
  module V1
    class StaffController < BaseController
      before_action :require_company!
      before_action :require_staff_manager!
      before_action :set_staff_member, only: [ :show, :update ]

      # GET /api/v1/staff
      def index
        staff = current_company.staff_members.includes(:user, :coach, :assigned_role)
                               .joins(:assigned_role).order("roles.position", "roles.name")
        render json: { staff: staff.map { |s| StaffMemberSerializer.new(s).as_json } }
      end

      # GET /api/v1/staff/:id
      def show
        render json: { staff_member: StaffMemberSerializer.new(@staff_member).as_json }
      end

      # POST /api/v1/staff
      def create
        # A refused save raises RecordInvalid, which ApplicationController
        # answers with the same 422 every other write gives.
        staff_member = Team::Actions.create_staff!(
          company: current_company, by: current_user,
          user_attributes: user_params.to_h.symbolize_keys, staff_attributes: staff_params.to_h.symbolize_keys
        )
        render json: { staff_member: StaffMemberSerializer.new(staff_member).as_json }, status: :created
      end

      # PATCH /api/v1/staff/:id
      def update
        if Team::Actions.update_staff(@staff_member, company: current_company, by: current_user, staff_attributes: staff_params.to_h.symbolize_keys)
          render json: { staff_member: StaffMemberSerializer.new(@staff_member).as_json }
        else
          render_errors(@staff_member)
        end
      end

      private

      # Staff management is admin-only now — no in-company staff role has full
      # access anymore, so there's no "staff-superadmin" exception to make here.
      def require_staff_manager!
        render_forbidden unless current_user.admin?
      end

      def set_staff_member
        @staff_member = current_company.staff_members.find(params[:id])
      end

      def user_params
        params.require(:staff_member).permit(:first_name, :last_name, :email, :phone, :password, :locale)
      end

      def staff_params
        params.require(:staff_member).permit(:role, :role_id, :active, :coach_id, :birthdate)
      end
    end
  end
end
