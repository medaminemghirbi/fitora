require "rails_helper"

RSpec.describe SupportTicket, type: :model do
  let(:sample_path) { Rails.root.join("spec/fixtures/files/sample.png") }

  it "rejects a disallowed attachment content type" do
    ticket = build(:support_ticket)
    ticket.attachments.attach(
      io: File.open(sample_path), filename: "virus.exe", content_type: "application/x-msdownload", identify: false
    )

    expect(ticket).not_to be_valid
    expect(ticket.errors[:attachments]).to be_present
  end

  it "rejects more than MAX_ATTACHMENTS files" do
    ticket = build(:support_ticket)
    (SupportTicket::MAX_ATTACHMENTS + 1).times do |n|
      ticket.attachments.attach(io: File.open(sample_path), filename: "file#{n}.png", content_type: "image/png")
    end

    expect(ticket).not_to be_valid
    expect(ticket.errors[:attachments]).to be_present
  end

  it "accepts an allowed image attachment" do
    ticket = build(:support_ticket)
    ticket.attachments.attach(io: File.open(sample_path), filename: "screenshot.png", content_type: "image/png")

    expect(ticket).to be_valid
  end

  it "is valid with no attachments at all" do
    expect(build(:support_ticket)).to be_valid
  end
end
