require "rails_helper"

RSpec.describe Sms::TunisieSmsClient do
  describe "#send_message" do
    it "sends the SMS and returns the response body on success" do
      client = described_class.new(api_key: "test-key", sender: "Fitora")
      response = instance_double(Net::HTTPOK, is_a?: true, body: "OK")
      captured_uri = nil
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) do |get|
        captured_uri = get.uri
        response
      end
      allow(Net::HTTP).to receive(:start) { |*, &block| block.call(http) }

      result = client.send_message(mobile: "+21620000000", text: "Hello")

      expect(result).to eq("OK")
      expect(captured_uri.to_s).to start_with(described_class::BASE_URL)
      expect(captured_uri.query).to include("key=test-key")
      expect(captured_uri.query).to include("sender=Fitora")
      expect(captured_uri.query).to include("sms=Hello")
    end

    it "raises ConfigurationError when no api key is configured" do
      client = described_class.new(api_key: nil, sender: "Fitora")

      expect do
        client.send_message(mobile: "+21620000000", text: "Hello")
      end.to raise_error(described_class::ConfigurationError, "TUNISIESMS_API_KEY is not set")
    end

    it "raises RequestError when the HTTP call does not succeed" do
      client = described_class.new(api_key: "test-key", sender: "Fitora")
      response = instance_double(Net::HTTPBadRequest, is_a?: false, code: "400")
      http = instance_double(Net::HTTP, request: response)
      allow(Net::HTTP).to receive(:start) { |*, &block| block.call(http) }

      expect do
        client.send_message(mobile: "+21620000000", text: "Hello")
      end.to raise_error(described_class::RequestError, "TunisieSMS request failed (400)")
    end

    # "Remind" runs inside the web request: a gateway that hangs must not hold
    # a server thread for the library's default 60 + 60 seconds.
    it "gives up on a gateway that does not answer within its timeouts" do
      client = described_class.new(api_key: "test-key", sender: "Fitora")
      options = nil
      allow(Net::HTTP).to receive(:start) do |*args, **kwargs|
        options = kwargs.presence || args.last
        raise Net::ReadTimeout
      end

      expect do
        client.send_message(mobile: "+21620000000", text: "Hello")
      end.to raise_error(described_class::RequestError, "TunisieSMS did not answer (Net::ReadTimeout)")
      expect(options).to include(use_ssl: true, open_timeout: 5, read_timeout: 10)
    end
  end

  describe ".send_message" do
    it "delegates to a new instance built from the default credentials" do
      instance = instance_double(described_class)
      allow(described_class).to receive(:new).and_return(instance)
      allow(instance).to receive(:send_message).with(mobile: "+21620000000", text: "Hi").and_return("OK")

      result = described_class.send_message(mobile: "+21620000000", text: "Hi")

      expect(result).to eq("OK")
      expect(instance).to have_received(:send_message).with(mobile: "+21620000000", text: "Hi")
    end
  end
end
