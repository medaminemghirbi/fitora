module Web
  module Superadmin
    # What heads every invoice Fitora sends a gym: who issues it — raison
    # sociale, address, matricule fiscal, contact — and the TVA rate and
    # timbre fiscal an invoice in dinars carries. Each invoice keeps the
    # terms it was issued with (Invoice#freeze_tax_terms): a change here
    # applies from the next one.
    class BillingController < BaseController
      before_action :load_setting

      def show; end

      def update
        attrs = params.require(:billing).permit(*PlatformSetting::ISSUER_FIELDS, :vat_percent, :stamp_duty)
        stamp = attrs.delete(:stamp_duty)
        @setting.assign_attributes(attrs.merge(vat_percent: decimal(attrs[:vat_percent]), stamp_duty_millimes: millimes(stamp)))
        return render(:show, status: :unprocessable_content) unless @setting.save

        flash[:success] = helpers.ngt("common.saved")
        redirect_to "/superadmin/billing", status: :see_other
      end

      private

      # The settings, and the latest invoice for an amount, to preview.
      def load_setting
        @setting = PlatformSetting.current
        @latest = Invoice.where("amount_cents > 0").order(issued_at: :desc).first
      end

      # "19", "19,5", "1,000" as people type them; nil (refused by the model)
      # when it is no number at all.
      def decimal(value)
        BigDecimal(value.to_s.strip.tr(",", "."))
      rescue ArgumentError
        nil
      end

      def millimes(dinars) = decimal(dinars)&.*(1000)&.round
    end
  end
end
