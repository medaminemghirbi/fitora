module Web
  module Superadmin
    # What Fitora's two plans cost and the annual discount: SubscriptionPricing,
    # as GET and PATCH /api/v1/superadmin/subscription_pricing answer it —
    # set in one currency, shown converted into every other with its rate.
    # ?currency= is the currency the form shows; saving there makes it the
    # one the prices are set in.
    class PricingController < BaseController
      def show
        @pricing = JSON.parse(SubscriptionPricing.payload(SubscriptionPricing.currency(params[:currency])).to_json).deep_symbolize_keys
      end

      def update
        currency = SubscriptionPricing.currency(params[:currency])
        plans = params[:plans].present? ? params[:plans].permit(*SubscriptionPrice::PLANS).to_h : {}
        discount = params[:annual_discount_percent] if params.key?(:annual_discount_percent)
        errors = SubscriptionPricing.update(currency, plans: plans, discount: discount)
        return render_refusal(errors) if errors.any?

        # The Angular page says "Enregistrer" (common.save) here (B-13).
        flash[:success] = helpers.ngt("common.saved")
        head :no_content
      end

      # POST …/pricing/rates — today's rates now, rather than tonight
      # (RefreshExchangeRatesJob); a source that fails keeps the ones there
      # were, and says so.
      def refresh_rates
        ExchangeRate.refresh!
        flash[:success] = helpers.ngt("superadmin.pricing_rates_refreshed")
        redirect_to "/superadmin/pricing", status: :see_other
      rescue ExchangeRate::Unavailable => e
        Rails.error.report(e, handled: true, context: { source: ExchangeRate::SOURCE_URL })
        flash[:error] = helpers.ngt("superadmin.pricing_rates_failed")
        redirect_to "/superadmin/pricing", status: :see_other
      end
    end
  end
end
