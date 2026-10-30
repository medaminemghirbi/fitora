# What a gym holds of someone it asked to add (MembershipRequest): only what
# it sent itself. Nothing from the person's record — not their id, nor the
# name and phone they or another gym recorded. The address is the one the gym
# typed, masked as everywhere else (EmailMask).
class MembershipRequestSerializer
  def initialize(request)
    @request = request
  end

  def as_json(*)
    {
      id: @request.id,
      status: "pending",
      first_name: @request.person["first_name"],
      last_name: @request.person["last_name"],
      phone: @request.person["phone"],
      email: EmailMask.call(@request.client.email),
      sent_at: @request.sent_at,
      expires_at: @request.expires_at
    }
  end
end
