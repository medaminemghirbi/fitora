# Settings → Application mobile: a salle's two keys — the member code and
# the coach key — with their QR codes, and replacing one; for
# /api/v1/mobile_app and the web UI's settings (moved unchanged from
# Api::V1::MobileAppController).
module MobileAppKeys
  AUDIENCES = %w[member coach].freeze

  def self.as_json(company)
    company.ensure_app_keys!
    {
      member_code: company.app_code,
      coach_key: company.coach_key,
      member_qr_svg: qr_svg(company.app_code),
      coach_qr_svg: qr_svg(company.coach_key)
    }
  end

  # A new key for that audience; the old one stops pairing at once. Audited.
  def self.regenerate!(company, audience:, by:)
    company.ensure_app_keys!.regenerate_app_key!(audience)
    AuditLog.record!(
      company: company, user: by, action: "mobile_app.key_regenerated",
      auditable: company, metadata: { audience: audience }
    )
    company
  end

  def self.qr_svg(text)
    RQRCode::QRCode.new(text).as_svg(module_size: 4, standalone: true, use_path: true, viewbox: true)
  end
  private_class_method :qr_svg
end
