# Everything the shell needs to know about a signed-in staff login, in one
# hash: the user, their salle, its branding, what they may do, what the
# product offers here, and where the subscription stands.
#
# The JSON GET /api/v1/bootstrap answers (Angular SPA, mobile app), and what
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
      modules: company&.enabled_module_keys || [],
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
      subscription: subscription_json,
      onboarding: user.admin? ? company&.onboarding_state&.as_json : nil,
      notifications: { unread_count: user.notifications.unread.count }
    }
  end

  private

  attr_reader :user, :company

  def subscription_json
    subscription = company&.subscription
    return nil if subscription.nil?

    {
      active: subscription.active,
      locked: subscription.locked?,
      lock_reason: subscription.lock_reason,
      # Enough for the shell to warn before the door shuts, rather than
      # leaving the admin to discover it mid-task.
      current_period_paid: subscription.current_period_paid?,
      days_before_lock: subscription.days_before_lock,
      # The shell counts the free days down instead of the unpaid ones.
      trial: subscription.trial?,
      trial_days_left: subscription.trial_days_left,
      # The account's plan, and what it opens: screens offering the
      # member app, or another salle, say "Pro" instead of a button
      # that would be refused.
      plan: subscription.plan,
      member_app: subscription.member_app?,
      multi_salle: subscription.multi_salle?,
      # Pro's tools: several salles, custom roles, branding, CSV
      # import / export. A paid Pro period only — locked on the trial.
      pro_features: subscription.pro_features?
    }
  end
end
