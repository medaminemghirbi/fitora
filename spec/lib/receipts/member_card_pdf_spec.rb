require "rails_helper"

RSpec.describe Receipts::MemberCardPdf do
  include PngHelper

  let(:company) { create(:company) }
  let(:client) { create(:client, company: company, first_name: "Salma", last_name: "Ben Ali") }
  let(:membership) { client.membership_for(company) }

  it "is one bank-card-sized page" do
    pdf = described_class.call(membership: membership)

    expect(pdf.byteslice(0, 4)).to eq("%PDF")
    expect(pdf).to include("/MediaBox [0 0 242.65 153.07]")
  end

  it "draws the photo when there is one Prawn can print, and leaves off one it cannot" do
    without = described_class.call(membership: membership)
    membership.photo.attach(io: Rails.root.join("spec/fixtures/files/sample.png").open, filename: "photo.png", content_type: "image/png")
    with = described_class.call(membership: membership.reload)
    expect(with.bytesize).to be > without.bytesize

    membership.photo.attach(io: png_declaring(5000, 5000), filename: "huge.png", content_type: "image/png")
    expect { described_class.call(membership: membership.reload) }.not_to raise_error
  end
end
