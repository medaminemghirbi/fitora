module Web
  # The catalogue's one copy of what the gym sells (CatalogueStore), for
  # the pages that render its tools: the catalogue itself, and the
  # onboarding flow, which embeds the same activities and formules tools.
  module CatalogueData
    extend ActiveSupport::Concern

    included do
      helper_method :catalogue, :packs_enabled?, :search_term, :list_page
    end

    private

    # As the three list endpoints return it, plus the platform's catalogue
    # the activity picker offers.
    def catalogue
      @catalogue ||= {
        activities: CatalogueListing.activities(current_company).map { |a| ActivitySerializer.new(a).as_json },
        plans: CatalogueListing.plans(current_company).map { |p| ContractTypeSerializer.new(p).as_json },
        packs: packs_enabled? ? CatalogueListing.packs(current_company).map { |p| PackSerializer.new(p).as_json } : [],
        templates: ActivityTemplate.active.catalogue_order.map { |t| ActivityTemplateSerializer.new(t).as_json }
      }
    end

    def packs_enabled?
      current_company.feature?(:packs)
    end

    def search_term
      params[:q].to_s
    end

    def list_page
      [ params[:page].to_i, 1 ].max
    end
  end
end
