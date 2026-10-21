require "rails_helper"

RSpec.describe Web::Translations do
  describe ".translate, as ngx-translate translates" do
    it "reads the Angular app's own words" do
      expect(described_class.translate("nav.clients", locale: :fr)).to eq("Adhérents")
      expect(described_class.translate("nav.clients", locale: :ar)).to eq(JSON.parse(Rails.root.join("config/locales/web/ng/ar.json").read).dig("nav", "clients"))
    end

    it "fills {{ placeholders }}, and leaves one without a value as written" do
      expect(described_class.translate("clients.sessions_left", { count: 3 }, locale: :fr)).to eq("3 séance(s) restante(s)")
      expect(described_class.translate("clients.sessions_left", {}, locale: :fr)).to include("{{")
    end

    it "falls back to French, then to the key itself" do
      I18n.backend.store_translations(:fr, ng: { spec_only: { word: "mot" } })
      expect(described_class.translate("spec_only.word", locale: :en)).to eq("mot")
      expect(described_class.translate("no.such.key", locale: :fr)).to eq("no.such.key")
    end
  end

  # Asked for by the Angular templates too, and missing from its files:
  # ngx-translate prints the key, and so does the web UI until the word is
  # added to both (MIGRATION_AUDIT §10, K-10).
  angular_missing = %w[common.clear]

  it "every key a web template asks for exists in all three languages" do
    keys = Rails.root.glob("app/{views/web,views/layouts/web,helpers/web,controllers/web}/**/*.{erb,rb}")
                .flat_map { |path| path.read.scan(/ngt\("([a-z0-9_.]+)"/).flatten }.uniq - angular_missing
    expect(keys.size).to be > 50

    %w[fr en ar].each do |locale|
      words = JSON.parse(Rails.root.join("config/locales/web/ng/#{locale}.json").read)
      missing = keys.reject { |key| words.dig(*key.split(".")).is_a?(String) }
      expect(missing).to be_empty, "#{locale}.json lacks #{missing.join(', ')}"
    end
  end
end

RSpec.describe Web::DateFormat do
  let(:time) { Time.find_zone("Africa/Tunis").parse("2026-10-14 10:00") }

  it "writes DatePipe's \"d MMM y\" with Angular's own month words" do
    expect(described_class.angular(time, "d MMM y", locale: :fr)).to eq("14 oct. 2026")
    expect(described_class.angular(time, "d MMM y", locale: :en)).to eq("14 Oct 2026")
    expect(described_class.angular(time, "d MMM y", locale: :ar)).to eq("14 أكتوبر 2026")
  end

  it "writes the browser's Intl formats, in each language's order" do
    expect(described_class.intl(time, :day_month_short, locale: :fr)).to eq("14 oct.")
    expect(described_class.intl(time, :day_month_short, locale: :en)).to eq("Oct 14")
    expect(described_class.intl(time, :weekday_day_month_long, locale: :fr)).to eq("mercredi 14 octobre")
    expect(described_class.intl(time, :weekday_day_month_long, locale: :en)).to eq("Wednesday, October 14")
    expect(described_class.intl(time, :weekday_day_month_long, locale: :ar)).to eq("الأربعاء، 14 أكتوبر")
  end

  it "reproduces every sample string Chromium wrote, in every language and format" do
    described_class::WORDS.fetch("intl").each do |locale, formats|
      formats.each do |name, spec|
        spec.fetch("samples").each do |sample|
          expect(described_class.intl(Time.iso8601(sample["iso"]).utc, name, locale: locale)).to eq(sample["text"]), "#{locale} #{name} #{sample['iso']}"
        end
      end
    end
  end

  it "reproduces every string Angular's own DatePipe wrote, in every language and pattern" do
    described_class::WORDS.fetch("angular").each do |locale, data|
      data.fetch("samples").each do |sample|
        expect(described_class.angular(Time.iso8601(sample["iso"]).utc, sample["pattern"], locale: locale)).to eq(sample["text"]), "#{locale} #{sample['pattern']} #{sample['iso']}"
      end
    end
  end

  it "writes the DatePipe patterns the pages use" do
    expect(described_class.angular(time, "dd/MM/yyyy", locale: :fr)).to eq("14/10/2026")
    expect(described_class.angular(time, "EEEE d MMMM y, HH:mm", locale: :fr)).to eq("mercredi 14 octobre 2026, 10:00")
  end

  it "capitalises the first letter only, as the sign-in panel does" do
    expect(described_class.capitalize_first("mercredi 14 octobre")).to eq("Mercredi 14 octobre")
  end
end
