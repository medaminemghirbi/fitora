module Web
  # Where a gym's request to add someone lands (MembershipRequest): the
  # emailed link opens the question, and only the button answers it — a
  # mail scanner that opens the link joins no one. Nobody signs in: the
  # link reached the person's inbox, which is what the request asks.
  class MembershipRequestsController < BaseController
    layout "web/auth"

    # GET /adhesion?token=
    def show
      @membership_request = MembershipRequest.find_by_token(params[:token])
      render status: @membership_request ? :ok : :not_found
    end

    # PATCH /adhesion { token }
    def update
      @membership_request = MembershipRequest.find_by_token(params[:token])
      return render(:show, status: :not_found) if @membership_request.nil?

      @gym_name = @membership_request.company.name
      @membership_request.accept!
      @accepted = true
      render :show
    end

    private

    def rate_limited
      @error = helpers.ngt("auth.too_many_attempts")
      render :show, status: :too_many_requests
    end
  end
end
