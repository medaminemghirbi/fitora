# Saving a salle's own profile — details, hours, booking rules, branding,
# what its contracts print — for PATCH /api/v1/company and the web UI's
# settings (moved unchanged from Api::V1::CompaniesController).
module CompanyProfile
  # currency + locale are tenant-wide settings a Fitora superadmin manages
  # (Api::V1::Superadmin::CompaniesController#update_settings); the admin only
  # picks a currency once, at signup. A signature is taken off with
  # remove_signature, never by sending an empty file. Branding (logo, colour,
  # identifier) is a Pro tool: on Starter it is dropped rather than refused,
  # so the rest of the form still saves. Returns whether it saved; the
  # errors are on the company.
  def self.update(company, params)
    company.signature.purge if ActiveModel::Type::Boolean.new.cast(params.dig(:company, :remove_signature))
    company.update(attributes(params, branding: company.pro_features?).except(:currency))
  end

  # The permitted company attributes of a request. branding: false leaves out
  # the logo, the colour and the identifier — Starter's update.
  def self.attributes(params, branding: true)
    permitted = params.require(:company).permit(
      :name, :description, :phone, :email, :country, :city,
      :address, :latitude, :longitude, :timezone, :currency,
      :slug, :logo,
      # Who signs the gym's contracts, and what they print (Settings).
      :signature, :signatory_name, :contract_terms,
      # Hours and branding are settings now, but the app still sends them
      # flat. Accept them where they have always been and fold them in.
      :primary_color, :business_hours_start, :business_hours_end,
      working_days: [],
      settings: [
        { features: CompanySettings::FEATURES.keys },
        { booking: CompanySettings::BOOKING.keys },
        { hours: [ :start, :end, { working_days: [] } ] },
        { branding: CompanySettings::BRANDING.keys }
      ]
    )

    unless branding
      permitted = permitted.except(:slug, :logo, :primary_color)
      permitted[:settings] = permitted[:settings].except(:branding) if permitted[:settings]
    end

    fold_legacy_settings_keys(permitted)
  end

  # Moves the flat hours/branding keys into the settings patch, so the
  # `settings` section wins over the flat key for the same value.
  def self.fold_legacy_settings_keys(permitted)
    hours = {
      start: permitted.delete(:business_hours_start),
      end: permitted.delete(:business_hours_end),
      working_days: permitted.delete(:working_days)
    }.compact
    branding = { primary_color: permitted.delete(:primary_color) }.compact

    return permitted if hours.empty? && branding.empty?

    settings = (permitted[:settings] || {}).to_h.symbolize_keys
    settings[:hours] = hours.merge((settings[:hours] || {}).to_h.symbolize_keys)
    settings[:branding] = branding.merge((settings[:branding] || {}).to_h.symbolize_keys)
    permitted[:settings] = settings
    permitted
  end
  private_class_method :fold_legacy_settings_keys
end
