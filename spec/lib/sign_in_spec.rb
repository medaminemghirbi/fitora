require "rails_helper"

# The sign-in's answer is the same for an unknown address and a wrong
# password; so is the time it takes: one password check each.
RSpec.describe SignIn do
  let(:company) { create(:company) }
  let!(:admin) { company.admin }
  let!(:member) { create(:client, company: company, password: "member-pass-1") }
  let!(:superadmin) { create(:user, :superadmin) }

  # How many passwords the block checked (bcrypt's one slow step).
  def password_checks
    SignIn.call("warm-up@fitora.test", "x") # the unknown address's digest, made once
    checks = 0
    allow(BCrypt::Password).to receive(:new).and_wrap_original { |original, *args| checks += 1; original.call(*args) }
    yield
    checks
  end

  it "checks one password for an address with no account, as for a wrong password" do
    expect(password_checks { expect(SignIn.call("nobody@fitora.test", "guess-1").error).to eq(:invalid_credentials) }).to eq(1)
    expect(password_checks { expect(SignIn.call(admin.email, "guess-1").error).to eq(:invalid_credentials) }).to eq(1)
    expect(password_checks { expect(SignIn.call(member.email, "guess-1").error).to eq(:invalid_credentials) }).to eq(1)
  end

  it "does the same at the console's door" do
    expect(password_checks { expect(SignIn.superadmin("nobody@fitora.test", "guess-1")).to be_nil }).to eq(1)
    expect(password_checks { expect(SignIn.superadmin(superadmin.email, "guess-1")).to be_nil }).to eq(1)
  end

  it "refuses every password for an address with no account" do
    expect(SignIn.call("nobody@fitora.test", "")).not_to be_success
    expect(SignIn.superadmin("nobody@fitora.test", nil)).to be_nil
  end
end
