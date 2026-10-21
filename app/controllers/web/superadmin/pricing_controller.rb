module Web
  module Superadmin
    # What Fitora's two plans cost, per currency, and the annual discount
    # (SuperadminPricingComponent): SubscriptionPricing, as GET and PATCH
    # /api/v1/superadmin/subscription_pricing answer it. ?currency= is the
    # currency shown (M-05).
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
    end
  end
end
