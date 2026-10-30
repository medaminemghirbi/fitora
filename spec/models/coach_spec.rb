require "rails_helper"

RSpec.describe Coach do
  let(:company) { create(:company) }

  it "requires a first and last name" do
    coach = build(:coach, company: company, first_name: nil, last_name: nil)
    expect(coach).not_to be_valid
    expect(coach.errors[:first_name]).to be_present
    expect(coach.errors[:last_name]).to be_present
  end

  it "rejects a malformed email but allows a blank one" do
    expect(build(:coach, company: company, email: "not-an-email")).not_to be_valid
    expect(build(:coach, company: company, email: "")).to be_valid
  end

  it "takes an https photo address, or none, and nothing a screen could run or read from the device" do
    expect(build(:coach, company: company, photo_url: "https://cdn.example.com/sami.jpg")).to be_valid
    expect(build(:coach, company: company, photo_url: "")).to be_valid
    %w[javascript:alert(1) data:image/png;base64,AAAA file:///etc/passwd http://cdn.example.com/sami.jpg https:// not\ a\ url].each do |value|
      expect(build(:coach, company: company, photo_url: value)).not_to be_valid, value
    end
  end

  it "keeps saving a coach whose old photo address is not https" do
    coach = create(:coach, company: company)
    coach.update_columns(photo_url: "http://old.example.com/sami.jpg") # rubocop:disable Rails/SkipsModelValidations

    expect(coach.update(bio: "Coach EMS")).to be(true)
  end

  it "builds the full name from first and last name" do
    coach = build(:coach, first_name: "Sami", last_name: "Cherif")
    expect(coach.full_name).to eq("Sami Cherif")
  end

  describe ".active" do
    it "only returns active coaches" do
      active = create(:coach, company: company, active: true)
      inactive = create(:coach, company: company, active: false)

      expect(Coach.active).to include(active)
      expect(Coach.active).not_to include(inactive)
    end
  end

  describe "#birthday_today?" do
    it "is true when month and day match regardless of year" do
      coach = build(:coach, birthdate: Date.new(1990, 6, 15))

      expect(coach.birthday_today?(on: Date.new(2026, 6, 15))).to be true
      expect(coach.birthday_today?(on: Date.new(2026, 6, 16))).to be false
    end

    it "is false when there is no birthdate on file" do
      coach = build(:coach, birthdate: nil)
      expect(coach.birthday_today?(on: Date.current)).to be false
    end
  end

  describe "#destroy" do
    it "nullifies coach_id on sessions rather than deleting them" do
      coach = create(:coach, company: company)
      session = create(:session, activity: create(:activity, company: company), company: company, coach: coach)

      coach.destroy

      expect(session.reload.coach_id).to be_nil
    end
  end
end
