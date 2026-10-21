require "rails_helper"

# What a superadmin's change to an account tells its admin: a new plan is
# billed (an invoice to pay) and notified; the door opened or closed is
# notified and e-mailed.
RSpec.describe SuperadminActions do
  let(:superadmin) { create(:user, :superadmin) }
  let(:company) { create(:company) }
  let(:admin) { company.admin }
  let(:subscription) { company.subscription }

  before { Subscription.start_trial!(admin, currency: "TND") unless admin.subscription }

  def notifications(kind) = admin.notifications.where(kind: kind)

  describe "a change of plan" do
    [ [ nil, "starter" ], [ nil, "pro" ], [ "pro", "starter" ], [ "starter", "pro" ] ].each do |from, to|
      it "#{from || 'trial'} → #{to}: an invoice to pay, and a notification naming it" do
        subscription.update!(plan: from, billing_period: :monthly) if from
        subscription.invoices.due.delete_all

        described_class.update_subscription(company, { plan: to, billing_period: "monthly" }, by: superadmin)

        bill = subscription.reload.due_invoice
        expect(bill).to be_present
        expect(bill.plan).to eq(to)
        note = notifications("plan_changed").sole
        expect(note.data).to include("plan" => to, "plan_from" => from, "number" => bill.number, "currency" => bill.currency)
        expect(note.url).to eq("/admin/subscription")
      end
    end

    it "changes nothing about access until the money arrives, which settles the same bill" do
      described_class.update_subscription(company, { plan: "pro", billing_period: "monthly" }, by: superadmin)
      bill = subscription.reload.due_invoice
      expect(subscription).to be_trial

      paid = described_class.issue_invoice(company, by: superadmin)
      expect(paid.id).to eq(bill.id)
      expect(paid.reload).to be_paid
      expect(notifications("invoice_issued").sole.data["number"]).to eq(bill.number)
    end

    it "a new billing period re-prices the bill waiting, without a notification" do
      described_class.update_subscription(company, { plan: "starter", billing_period: "monthly" }, by: superadmin)
      described_class.update_subscription(company, { billing_period: "yearly" }, by: superadmin)

      expect(subscription.reload.due_invoice.amount_cents).to eq(subscription.annual_cents)
      expect(subscription.invoices.due.count).to eq(1)
      expect(notifications("plan_changed").count).to eq(1)
    end

    it "the same plan again bills nothing" do
      described_class.update_subscription(company, { plan: "starter" }, by: superadmin)
      expect { described_class.update_subscription(company, { plan: "starter" }, by: superadmin) }
        .not_to change { [ subscription.invoices.count, notifications("plan_changed").count ] }
    end
  end

  describe "the door" do
    it "closed: a notification and an e-mail" do
      expect { described_class.update_subscription(company, { active: false }, by: superadmin) }
        .to have_enqueued_mail(AccountMailer, :access_suspended).with(admin)
      expect(notifications("access_suspended").count).to eq(1)
    end

    it "opened again: a notification and an e-mail" do
      subscription.update!(active: false)
      expect { described_class.update_subscription(company, { active: true }, by: superadmin) }
        .to have_enqueued_mail(AccountMailer, :access_restored).with(admin)
      expect(notifications("access_restored").count).to eq(1)
    end
  end

  it "the e-mails say what happened, and where to look" do
    suspended = AccountMailer.access_suspended(admin)
    expect(suspended.subject).to eq("Votre accès Fitora est suspendu")
    expect(suspended.to).to eq([ admin.email ])
    expect(suspended.body.encoded).to include("/admin/subscription")

    subscription.update!(plan: :pro)
    restored = AccountMailer.access_restored(admin)
    expect(restored.subject).to eq("Votre accès Fitora est rétabli")
    expect(restored.body.encoded).to include("Pro")
  end
end
