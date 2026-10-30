module DataExchange
  # CSV round-trip for the client roster — the most common migration path
  # for a gym coming from another system (spreadsheet or a competitor export).
  class Clients
    HEADERS = %w[first_name last_name email phone].freeze
    ALREADY_ON_FITORA = "This email already has a Fitora account: add this member from the Members page, so they can accept.".freeze
    EXAMPLE_ROW = [ "Amine", "Test", "amine@example.com", "+21620000000" ].freeze

    def self.template_csv
      CsvSafe.generate do |csv|
        csv << HEADERS
        csv << EXAMPLE_ROW
      end
    end

    def self.export_csv(company)
      CsvSafe.generate do |csv|
        csv << HEADERS
        company.clients.order(:created_at).find_each do |client|
          csv << [ client.first_name, client.last_name, client.email, client.phone ]
        end
      end
    end

    # An email Fitora already knows, for someone this gym does not train, is
    # refused with its row rather than joined: the person has to agree first
    # (MembershipRequest), and a file of addresses must not become a way to
    # read, or to mail, other gyms' members. The gym adds them one by one
    # from the members page, which sends them the request. Its own members
    # are left as they are.
    def self.import_csv(company:, user:, io:)
      Importer.run(io) do |row|
        email = row["email"].to_s.strip
        client = Client.find_by_email(email) || Client.new(email: email.presence)
        next ALREADY_ON_FITORA if client.consent_needed_to_join?(company)

        if client.new_record?
          client.assign_attributes(
            first_name: row["first_name"].to_s.strip,
            last_name: row["last_name"].to_s.strip,
            phone: row["phone"].to_s.strip
          )
        end

        ActiveRecord::Base.transaction do
          client.save!
          client.join!(company)
        end
        nil
      rescue ActiveRecord::RecordInvalid => e
        e.record.errors.full_messages.join(", ")
      end
    end
  end
end
