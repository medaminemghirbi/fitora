require "rails_helper"

# Every sample is Chromium's own Number#toLocaleString (extract-date-words.mjs).
RSpec.describe Web::NumberFormat do
  Web::DateFormat::WORDS.fetch("numbers").each do |locale, spec|
    spec["samples"].each do |sample|
      it "prints #{sample['n']} in #{locale} as #{sample['text'].inspect}" do
        expect(described_class.locale_string(sample["n"], locale: locale)).to eq(sample["text"])
      end
    end
  end
end
