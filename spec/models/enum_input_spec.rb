require "rails_helper"

# Enums whose value comes from a request body. One the enum does not know
# is a validation error — a 422 — not an ArgumentError, a 500.
RSpec.describe "Enums set from a request" do
  {
    Session => :status, RecurringSchedule => :recurrence_type, Activity => :session_format,
    ContractType => :billing_period, Payment => :payment_method
  }.each do |model, attribute|
    it "#{model.name}##{attribute} refuses an unknown value" do
      record = model.new
      expect { record.public_send("#{attribute}=", "bogus") }.not_to raise_error

      record.validate
      expect(record.errors[attribute]).to include("is not included in the list")
    end
  end
end
