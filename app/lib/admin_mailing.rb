# The console's mailing: a subject and a text, with variables each admin gets
# their own values for, sent to the admin accounts a superadmin picked. One job
# per recipient (DeliverMailingJob), so a mail that fails is that recipient's
# alone and the page can say so.
module AdminMailing
  # Anything between double braces, so a typo ({{prénom}}) is refused rather
  # than reaching a customer as it was typed.
  PLACEHOLDER = /\{\{\s*([^{}]*?)\s*\}\}/
  VARIABLES = %w[prenom nom salle ville email lien_connexion].freeze

  module_function

  # What an admin's variables say. Nothing secret belongs here: it is shown in
  # the composer's preview and goes out by e-mail.
  def values_for(admin)
    salles = admin.companies.sort_by(&:created_at)
    {
      "prenom" => admin.first_name,
      "nom" => admin.last_name,
      "salle" => salles.map(&:name).join(", "),
      "ville" => salles.filter_map { |salle| salle.city.presence }.uniq.join(", "),
      "email" => admin.email,
      "lien_connexion" => "#{Rails.configuration.x.frontend_url}/connexion"
    }
  end

  def fill(text, values)
    text.to_s.gsub(PLACEHOLDER) { values.fetch(Regexp.last_match(1), "") }
  end

  # The mailing, saved and on its way, or carrying its errors. Only active admin
  # accounts can receive one, whatever ids the form sent.
  def start(attributes, admin_ids, by:)
    mailing = Mailing.new(attributes.to_h.merge(sent_by: by))
    admins = User.admin.active.where(id: Array(admin_ids).compact_blank).to_a
    mailing.valid?
    mailing.errors.add(:recipients, :blank) if admins.empty?
    return mailing if mailing.errors.any?

    Mailing.transaction do
      mailing.save!
      admins.each { |admin| mailing.recipients.create!(user: admin, email: admin.email) }
    end
    ActiveJob.perform_all_later(mailing.recipients.map { |recipient| DeliverMailingJob.new(recipient.id) })
    mailing
  end
end
