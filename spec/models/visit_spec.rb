require "rails_helper"

RSpec.describe Visit do
  let(:company) { create(:company) }
  let(:desk) { company.admin }
  let(:client) { create(:client, company: company, first_name: "Salma") }
  let(:plan) { create(:contract_type, company: company, name: "Mensuel") }

  def subscribe(**attrs)
    create(:contract, client: client, contract_type: plan, payment_status: :paid, **attrs)
  end

  describe ".verdict_for" do
    it "is green for a member with a running, paid subscription" do
      contract = subscribe
      verdict = described_class.verdict_for(client, company)

      expect([ verdict.tone, verdict.reason, verdict.notices ]).to eq([ "green", nil, [] ])
      expect(verdict.contract).to eq(contract)
    end

    it "is red with the reason when there is nothing to come in on" do
      expect(described_class.verdict_for(client, company).reason).to eq("no_subscription")

      lapsed = subscribe(starts_at: 40.days.ago, expires_at: 10.days.ago)
      verdict = described_class.verdict_for(client, company)
      expect([ verdict.tone, verdict.reason, verdict.contract ]).to eq([ "red", "expired", lapsed ])
    end

    it "says why a subscription that exists does not open the door" do
      paused = subscribe(paused_at: 1.day.ago)
      expect(described_class.verdict_for(client, company).reason).to eq("paused")

      paused.update!(paused_at: nil, starts_at: 3.days.from_now, expires_at: 33.days.from_now)
      expect(described_class.verdict_for(client, company).reason).to eq("not_started")

      counted = create(:contract_type, company: company, unlimited_bookings: false, booking_limit: 10, session_count: 10)
      paused.update!(contract_type: counted, starts_at: 1.day.ago, remaining_bookings: 0)
      expect(described_class.verdict_for(client, company).reason).to eq("no_sessions_left")
    end

    it "is red for money owed, and for a member the gym deactivated" do
      create(:contract, client: client, contract_type: plan, payment_status: :unpaid)
      verdict = described_class.verdict_for(client, company)
      expect([ verdict.reason, verdict.balance.to_f ]).to eq([ "unpaid", 89.0 ])

      client.membership_for(company).update!(active: false)
      expect(described_class.verdict_for(client, company).reason).to eq("inactive")
    end

    it "is amber when the member is let in with something to say", :midday do
      subscribe(expires_at: 2.days.from_now)
      described_class.create!(company: company, client: client, checked_in_at: 3.hours.ago)
      verdict = described_class.verdict_for(client, company)

      expect([ verdict.tone, verdict.notices ]).to eq([ "amber", %w[already_in expires_soon] ])
    end

    it "only reads this gym's subscriptions" do
      elsewhere = create(:company)
      client.join!(elsewhere)
      create(:contract, client: client, contract_type: create(:contract_type, company: elsewhere), payment_status: :paid)

      expect(described_class.verdict_for(client, company).reason).to eq("no_subscription")
    end
  end

  describe ".admit!" do
    it "records the visit against the running subscription" do
      contract = subscribe
      visit = described_class.admit!(client: client, company: company, by: desk)

      expect(visit).to have_attributes(contract: contract, checked_in_by: desk, forced: false, reason: nil, consumed_session: false)
    end

    it "refuses a red verdict unless forced — and then records it, audited" do
      expect { described_class.admit!(client: client, company: company, by: desk) }
        .to raise_error(ApplicationRecord::Refused) { |e| expect(e.key).to eq("entries.errors.no_subscription") }

      visit = described_class.admit!(client: client, company: company, by: desk, force: true)
      expect(visit).to have_attributes(forced: true, reason: "no_subscription")
      expect(AuditLog.where(action: "visit.forced", auditable_id: visit.id)).to exist
    end

    it "is one visit for a card scanned twice in a row" do
      subscribe
      first = described_class.admit!(client: client, company: company, by: desk)
      second = described_class.admit!(client: client, company: company, by: desk)

      expect(second).to eq(first)
      travel 3.minutes do
        expect(described_class.admit!(client: client, company: company, by: desk)).not_to eq(first)
      end
    end

    context "with a counted formule" do
      let(:plan) { create(:contract_type, company: company, unlimited_bookings: false, booking_limit: 10, session_count: 10) }

      it "takes a session for the visit, and gives it back when the visit is undone" do
        contract = subscribe(remaining_bookings: 3)
        visit = described_class.admit!(client: client, company: company, by: desk)
        expect([ visit.consumed_session, contract.reload.remaining_bookings ]).to eq([ true, 2 ])

        visit.undo!
        expect(contract.reload.remaining_bookings).to eq(3)
        expect(described_class.count).to eq(0)
      end

      it "takes nothing when a class booked today already did", :midday do
        contract = subscribe(remaining_bookings: 3)
        session = create(:session, activity: contract.activity, company: company, starts_at: 1.hour.from_now)
        create(:booking, client: client, session: session, contract: contract, amount: 0)

        visit = described_class.admit!(client: client, company: company, by: desk)
        expect([ visit.consumed_session, contract.reload.remaining_bookings ]).to eq([ false, 3 ])
      end

      it "never takes one off a subscription that is not running" do
        lapsed = subscribe(remaining_bookings: 4, starts_at: 40.days.ago, expires_at: 10.days.ago)
        visit = described_class.admit!(client: client, company: company, by: desk, force: true)

        expect([ visit.reason, visit.consumed_session, lapsed.reload.remaining_bookings ]).to eq([ "expired", false, 4 ])
      end
    end
  end
end
