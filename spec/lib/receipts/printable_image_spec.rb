require "rails_helper"

RSpec.describe Receipts::PrintableImage do
  let(:company) { create(:company) }

  # An image stored before the ceiling existed: attached without the
  # model's validations.
  def stored_signature(io)
    blob = ActiveStorage::Blob.create_and_upload!(io: io, filename: "signature.png", content_type: "image/png")
    ActiveStorage::Attachment.create!(name: "signature", record: company, blob: blob)
    company.reload.signature
  end

  it "hands Prawn an ordinary PNG" do
    signature = stored_signature(Rails.root.join("spec/fixtures/files/sample.png").open)

    expect(described_class.io(signature).read(8)).to eq("\x89PNG\r\n\x1A\n".b)
  end

  # Prawn would decode 20,000 × 20,000 pixels — 1.6 GB — for every PDF.
  it "leaves off a PNG too large to draw, read from its header alone" do
    signature = stored_signature(png_declaring(20_000, 20_000))
    expect_any_instance_of(ActiveStorage::Blob).not_to receive(:download)

    expect(described_class.io(signature)).to be_nil
  end

  it "still prints the contract, without the image" do
    stored_signature(png_declaring(20_000, 20_000))
    contract = create(:contract, client: create(:client, company: company), contract_type: create(:contract_type, company: company))

    expect(Receipts::ContractAgreementPdf.call(contract: contract).byteslice(0, 4)).to eq("%PDF")
  end
end
