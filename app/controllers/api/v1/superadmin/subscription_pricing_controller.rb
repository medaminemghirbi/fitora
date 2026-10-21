module Api
  module V1
    module Superadmin
      # What each plan (Starter, Pro) costs per month in each currency, plus
      # the global annual-billing discount (SubscriptionPricing).
      # Superadmin-only.
      class SubscriptionPricingController < BaseController
        before_action :require_superadmin!

        # GET /api/v1/superadmin/subscription_pricing?currency=EUR — both
        # plans for one currency at once (defaults to
        # SubscriptionPrice::REFERENCE_CURRENCY, TND, when omitted).
        def show
          render json: SubscriptionPricing.payload(SubscriptionPricing.currency(params[:currency]))
        end

        # PATCH /api/v1/superadmin/subscription_pricing?currency=EUR
        #   { plans: { "starter" => monthly_cents, "pro" => ... }, annual_discount_percent? }
        # Either plan may be sent alone — an omitted one is left as-is.
        def update
          currency = SubscriptionPricing.currency(params[:currency])
          plans = params[:plans].present? ? params[:plans].permit(*SubscriptionPrice::PLANS).to_h : {}
          discount = params[:annual_discount_percent] if params.key?(:annual_discount_percent)
          errors = SubscriptionPricing.update(currency, plans: plans, discount: discount)
          return render json: { error: errors.first, errors: errors }, status: :unprocessable_content if errors.any?

          render json: SubscriptionPricing.payload(currency)
        end
      end
    end
  end
end
