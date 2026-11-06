# Everything the shell needs to know about a signed-in staff login, in one
# hash: the user, their salle, its branding, what they may do and what the
# product offers here.
#
# The JSON GET /api/v1/bootstrap answers (the mobile app), and what
# the server-rendered web UI reads to draw the same shell — one definition,
# so the two can never disagree about a permission or a banner.
class SessionBootstrap
  def initialize(user, company)
    @user = user
    @company = company
  end

  def as_json(*)
    {
      user: UserSerializer.new(user).as_json,
      company: user.admin? ? CompanySerializer.new(company).as_json : nil,
      branding: CompanyBrandingSerializer.new(company).as_json,
      role: user.role_summary,
      permissions: user.permission_keys,
      # Which parts of the product this tenant has turned on. Sent to
      # everyone, not just the admin (whose `company` payload also
      # carries them): a moderator needs to know rooms exist as much
      # as the admin does. It says what the product OFFERS here, never
      # who may use it — that is `permissions`, resolved separately.
      features: company&.settings&.features || {},
      roles: (company&.roles&.ordered || []).map { |r|
        { id: r.id, key: r.key, name: r.name, permissions: r.permissions, builtin: r.builtin }
      },
      permission_catalog: Permission::CATALOG,
      onboarding: user.admin? ? company&.onboarding_state&.as_json : nil,
      notifications: { unread_count: user.notifications.unread.count }
    }
  end

  private

  attr_reader :user, :company
end
