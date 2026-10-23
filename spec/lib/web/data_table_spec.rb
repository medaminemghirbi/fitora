require "rails_helper"

RSpec.describe Web::DataTable do
  let(:definition) do
    described_class::Definition.new(
      search: :name_cont,
      sorts: { name: "name", created: "created_at" },
      default: %w[created desc],
      filters: { status: { "open" => { active_eq: true }, "all" => {} }, plan: { "pro" => { plan_eq: "pro" } } },
      defaults: { status: "open" }
    )
  end

  def table(params = {}) = definition.table(ActionController::Parameters.new(params))

  it "reads the URL's own words, and takes anything else for the default" do
    t = table(search: "  zen  ", sort: "name", dir: "desc", status: "all", plan: "gold", limit: "50")
    expect([ t.term, t.sort, t.dir, t.filter(:status), t.filter(:plan), t.limit ]).to eq([ "zen", "name", "desc", "all", nil, 50 ])

    t = table(sort: "password_digest", limit: "7", status: "nope")
    expect([ t.sort, t.dir, t.filter(:status), t.limit ]).to eq([ "created", "desc", "open", 25 ])
    expect(table(search: "x" * 500).term.size).to eq(described_class::MAX_TERM)
  end

  it "writes the URL without what is the default, back on the first page" do
    expect(table.path("/t")).to eq("/t")
    expect(table(search: "zen", page: "3").path("/t")).to eq("/t?search=zen")
    expect(table(search: "zen").path("/t", page: 3)).to eq("/t?page=3&search=zen")
    expect(table(status: "all", limit: "100").path("/t", sort: "name", dir: "asc")).to eq("/t?dir=asc&limit=100&sort=name&status=all")
    expect(table(sort: "created", dir: "desc").path("/t")).to eq("/t")
  end

  it "turns a sorted column the other way round, and sorts any other ascending" do
    t = table(sort: "name", dir: "asc")
    expect([ t.next_dir(:name), t.next_dir(:created) ]).to eq(%w[desc asc])
    expect(table(sort: "name", dir: "desc").next_dir(:name)).to eq("asc")
  end

  it "is narrowed by a search or a filter off its default, not by its sort" do
    expect(table(sort: "name").narrowed?).to be(false)
    expect(table(status: "open").narrowed?).to be(false)
    expect(table(status: "all").narrowed?).to be(true)
    expect(table(search: "a").narrowed?).to be(true)
    expect(table(sort: "name", dir: "asc").kept_fields).to eq("sort" => "name", "dir" => "asc")
  end
end
