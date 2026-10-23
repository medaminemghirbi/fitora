module Web
  # One table of the superadmin console, as Administrate draws its
  # dashboards: a search box, filters, sortable columns and pages, all of it
  # in the URL (?search=&sort=&dir=&<filter>=&page=&limit=), so a table can
  # be reloaded, bookmarked and gone back to as it was.
  #
  # The URL speaks this table's own words — a column's key, a filter's
  # option — and they become Ransack conditions here, over what each model
  # allowlists for the console (ApplicationRecord.console_searchable).
  # Nothing from the request reaches Ransack as it came: an unknown column
  # or option is the default, and a condition naming anything the model has
  # not allowlisted raises (ransack!) rather than being quietly dropped.
  # Pagy pages the result (Web::Superadmin::BaseController#paginate).
  class DataTable
    # The rows-per-page choices; anything else in ?limit= is the first.
    LIMITS = [ 25, 50, 100 ].freeze
    # A search term past this is cut before it reaches the database.
    MAX_TERM = 100

    # search:   the Ransack predicate the box fills (:name_or_city_cont)
    # sorts:    column key → the attribute, or attributes, it orders by
    # default:  [column key, direction] when the URL asks for none
    # filters:  name → { option → Ransack conditions }; "all" maps to {}
    # defaults: name → the option shown when the URL names none
    # distinct: true when the search reaches through a has_many, which
    #           would otherwise list a row once per match
    Definition = Data.define(:search, :sorts, :default, :filters, :defaults, :distinct) do
      def initialize(search:, sorts:, default:, filters: {}, defaults: {}, distinct: false)
        super(search:, sorts: sorts.transform_keys(&:to_s), default:, filters: filters.transform_keys(&:to_s),
              defaults: defaults.transform_keys(&:to_s), distinct:)
      end

      def table(params) = DataTable.new(self, params)
    end

    attr_reader :term, :sort, :dir, :limit

    def initialize(definition, params)
      @definition = definition
      @term = params[:search].to_s.strip.first(MAX_TERM)
      key = params[:sort].to_s
      @sort, @dir = definition.sorts.key?(key) ? [ key, params[:dir] == "desc" ? "desc" : "asc" ] : definition.default
      @limit = LIMITS.include?(params[:limit].to_i) ? params[:limit].to_i : LIMITS.first
      @filters = definition.filters.to_h do |name, options|
        value = params[name].to_s
        [ name, options.key?(value) ? value : definition.defaults[name] ]
      end
    end

    # The scope, searched, filtered and sorted. Ties go to the primary key,
    # so a row never shows on two pages, nor on none.
    def apply(scope)
      conditions = {}
      conditions[@definition.search] = term if term.present?
      @filters.each { |name, value| conditions.merge!(@definition.filters.dig(name, value) || {}) }
      conditions[:s] = Array(@definition.sorts.fetch(sort)).map { |attribute| "#{attribute} #{dir}" }
      scope.ransack!(conditions, auth_object: :superadmin).result(distinct: @definition.distinct).order(:id)
    end

    def filter(name) = @filters[name.to_s]

    def sorted_by?(key) = sort == key.to_s

    # Anything narrowing the rows: the search, or a filter off its default.
    def narrowed?
      term.present? || @filters.any? { |name, value| value != @definition.defaults[name] }
    end

    # The direction a click on this column's header asks for: the other way
    # round when it is the sort already, ascending otherwise.
    def next_dir(key) = sorted_by?(key) && dir == "asc" ? "desc" : "asc"

    # The table as the URL writes it, with `changes` made, every default left
    # out, and back to the first page unless a page is given.
    def query(changes = {})
      state = { "search" => term, "sort" => sort, "dir" => dir, "limit" => limit, **@filters }
      state.merge!(changes.transform_keys(&:to_s))
      state.delete("sort") && state.delete("dir") if [ state["sort"], state["dir"] ] == @definition.default
      state.delete("limit") if state["limit"].to_i == LIMITS.first
      state.delete("page") if state["page"].to_i <= 1
      state.reject { |name, value| value.blank? || value == @definition.defaults[name] }
    end

    def path(base, changes = {})
      query = query(changes)
      query.empty? ? base : "#{base}?#{query.to_query}"
    end

    # What the toolbar's form carries besides its own inputs, so a new search
    # keeps the column it is sorted by. (The page size is the footer's own
    # select, in the same form.)
    def kept_fields = query.slice("sort", "dir")
  end
end
