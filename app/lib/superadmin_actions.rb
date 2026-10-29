# What a Fitora superadmin does to a gym's account, reached through any one
# of its salles: open or close its door, move its plan or its billing
# period, set the salle's currency and language, record a payment (an
# invoice) or take one back, and step inside to help. Called by the
# superadmin console (Web::Superadmin::CompaniesController). The audit-log
# actions are named as the API's were.
module SuperadminActions
  module_function

  # The ACCOUNT's subscription: whether the door is open (for every salle at
  # once), which plan it is on, and whether an invoice covers one month or
  # twelve. None of them ends a trial: only a paid invoice does
  # (#issue_invoice).
  #
  # The admin is told: a change of plan bills the account at once (an
  # invoice to pay, Subscription#bill!) and says so in a notification; the
  # door opened or closed is a notification and an e-mail. A new billing
  # period re-prices a bill still waiting, without a word.
  # `attrs`: any of :active, :billing_period, :plan. Returns the
  # subscription, saved or carrying its errors.
  def update_subscription(company, attrs, by:)
    subscription = company.subscription || company.admin.build_subscription
    was_active = subscription.active
    was_plan = subscription.plan
    was_period = subscription.billing_period

    saved = Subscription.transaction do
      subscription.update(attrs) && bill_change(subscription, was_plan, was_period, by)
    end
    if saved
      # Only a change of access is an access event. Picking what the next
      # invoice covers used to be logged as "access restored", which is what
      # the admin's feed then told them.
      action =
        if subscription.active != was_active
          subscription.active? ? "subscription.access_restored" : "subscription.access_suspended"
        elsif subscription.plan != was_plan then "subscription.plan_changed"
        else "subscription.billing_period_changed"
        end
      AuditLog.record!(
        company: company, user: by, action: action,
        auditable: subscription,
        metadata: {
          from: was_active, to: subscription.active, billing_period: subscription.billing_period,
          plan_from: was_plan, plan: subscription.plan
        }
      )
      tell_admin(company, subscription, was_plan: was_plan, was_active: was_active)
    end
    subscription
  end

  # The bill a change asks for: a new plan is billed; a new billing period
  # re-prices the bill already waiting. Truthy, for the transaction above.
  def bill_change(subscription, was_plan, was_period, by)
    if subscription.plan.present? && subscription.plan != was_plan
      subscription.bill!(issued_by: by)
    elsif subscription.billing_period != was_period && subscription.due_invoice
      subscription.bill!(issued_by: by)
    end
    true
  end

  def tell_admin(company, subscription, was_plan:, was_active:)
    admin = company.admin
    if subscription.plan.present? && subscription.plan != was_plan
      invoice = subscription.due_invoice
      Notification.push(
        recipient: admin, kind: "plan_changed",
        data: { plan_from: was_plan, plan: subscription.plan, number: invoice.number, amount: invoice.amount, currency: invoice.currency },
        url: "/admin/subscription", dedup_key: "plan_changed-#{invoice.id}-#{SecureRandom.uuid}"
      )
    end
    return if subscription.active == was_active

    kind = subscription.active? ? "access_restored" : "access_suspended"
    Notification.push(recipient: admin, kind: kind, data: { plan: subscription.plan }, url: "/admin/subscription",
                      dedup_key: "#{kind}-#{subscription.id}-#{SecureRandom.uuid}")
    AccountMailer.public_send(kind, admin).deliver_later
  end

  # Tenant-wide display settings a superadmin controls on the company's
  # behalf: the app language and the billing/display currency. Returns
  # whether they saved.
  def update_settings(company, attrs, by:)
    return false unless company.update(attrs)

    AuditLog.record!(
      company: company, user: by, action: "superadmin.settings_updated",
      auditable: company, metadata: { currency: company.currency, locale: company.locale }
    )
    true
  end

  # Stepping inside a gym's admin account, marked with who is really there.
  # Returns the admin, or nil when the gym has none.
  def impersonate(company, by:)
    admin = company.admin
    return nil if admin.nil?

    AuditLog.record!(
      company: company, user: admin, action: "superadmin.impersonation_started",
      auditable: company, metadata: { superadmin_id: by.id, superadmin_email: by.email }
    )
    admin
  end

  # The money arrived: one invoice for the next period the account has not
  # paid for, at its plan's price, opening access again for every salle.
  # Payment happens off-app, so this is the only record that it happened.
  # Raises ApplicationRecord::Refused with the API's words.
  def issue_invoice(company, by:, notes: nil)
    subscription = company.subscription
    raise ApplicationRecord::Refused, "This gym has no subscription." if subscription.nil?
    raise ApplicationRecord::Refused, "Choose a plan before recording a payment." if subscription.plan.nil?

    invoice = subscription.issue_invoice!(issued_by: by, notes: notes.presence)
    AuditLog.record!(
      company: company, user: by, action: "subscription.invoice_issued",
      auditable: invoice,
      metadata: { number: invoice.number, period_end: invoice.period_end, amount_cents: invoice.amount_cents }
    )
    Notification.push(
      recipient: company.admin, kind: "invoice_issued",
      data: { number: invoice.number, amount: invoice.amount, currency: invoice.currency },
      url: "/admin/subscription", dedup_key: "invoice-#{invoice.id}"
    )
    invoice
  end

  # An invoice issued in error. Deleting it takes the coverage back with it;
  # the sweep closes access again if that leaves the account uncovered.
  # Raises ActiveRecord::RecordNotFound for one that is not the account's.
  def void_invoice(company, invoice_id, by:)
    invoice = (company.subscription&.invoices || Invoice.none).find(invoice_id)
    number = invoice.number
    invoice.destroy!

    AuditLog.record!(
      company: company, user: by, action: "subscription.invoice_voided",
      auditable: company, metadata: { number: number }
    )
  end
end
