require "rails_helper"

RSpec.describe Web::AngularTemplate do
  # The line-keeping comments (see .lines) print nothing; compare without them.
  def transform(source) = described_class.transform(source).gsub(/<%#\n+%>/, "")

  it "keeps the template's line count, so errors point at the right line" do
    source = "<div>\n  <span>a</span>\n  <% if x %>\n    <b>\n      <%= y %>\n    </b>\n  <% end %>\n</div>\n"
    expect(described_class.transform(source).count("\n")).to eq(source.count("\n"))
  end

  it "compiles to ERB that renders" do
    source = described_class.transform("<%# ng: rail %>\n<ul>\n  <% [1, 2].each do |n| %>\n    <li>\n      <%= n %>\n    </li>\n  <% end %>\n</ul>")
    expect(ERB.new(source).result(binding)).to eq(%(<ul _ngcontent-rail=""><li _ngcontent-rail=""> 1 </li><li _ngcontent-rail=""> 2 </li></ul>))
  end

  describe "whitespace, as Angular's WhitespaceVisitor treats it" do
    it "drops whitespace-only text between tags" do
      expect(transform("<div>\n  <span>a</span>\n  <span>b</span>\n</div>")).to eq("<div><span>a</span><span>b</span></div>")
    end

    it "keeps text around an interpolation, collapsing runs to one space" do
      expect(transform("<label>\n  <%= t %>\n  <span>1</span>\n</label>")).to eq("<label> <%= t %> <span>1</span></label>")
    end

    it "keeps a single space between two interpolations" do
      expect(transform("<p><%= a %> <%= b %></p>")).to eq("<p><%= a %> <%= b %></p>")
    end

    it "treats control tags as boundaries, like @if blocks" do
      expect(transform("<td>\n  <% if x %>\n    <span>y</span>\n  <% end %>\n</td>")).to eq("<td><% if x %><span>y</span><% end %></td>")
    end

    it "treats element-producing output (render, link_to…) as an element" do
      expect(transform("<div>\n  <%= render \"x\" %>\n</div>")).to eq("<div><%= render \"x\" %></div>")
    end

    it "treats a formatted date or amount (ng_date, ng_money) as text, and only ng_highlight as markup" do
      expect(transform("<td>\n  <%= ng_date(a) %>\n  <span>→</span>\n  <%= ng_money(b) %>\n</td>"))
        .to eq("<td> <%= ng_date(a) %> <span>→</span> <%= ng_money(b) %>\n</td>")
      expect(transform("<div>\n  <%= ng_highlight(a) %>\n</div>")).to eq("<div><%= ng_highlight(a) %></div>")
    end

    it "treats a <template>'s content like any other markup (it is inserted later, inline)" do
      expect(transform("<template>\n  <div>a</div>\n  <div>b</div>\n</template>")).to eq("<template><div>a</div><div>b</div></template>")
    end

    it "leaves <pre>, <textarea>, <script> and <style> content alone" do
      source = "<textarea>\n  keep  this\n</textarea>"
      expect(transform(source)).to eq(source)
    end

    it "is not fooled by > inside an attribute or ERB in a tag" do
      expect(transform(%(<a href="<%= path %>" data-x="a>b">\n  go\n</a>))).to eq(%(<a href="<%= path %>" data-x="a>b"> go\n</a>))
    end

    it "collapses runs of two or more, and keeps a lone newline, as Angular does" do
      expect(transform("<p>a\nb  c</p>")).to eq("<p>a\nb c</p>")
    end

    it "keeps literal text intact apart from whitespace runs" do
      expect(transform("<p>Bon   retour.</p>")).to eq("<p>Bon retour.</p>")
    end
  end

  describe "scoping, as Angular's emulated encapsulation marks elements" do
    it "marks every element of a scoped template, and nothing without the directive" do
      expect(transform("<%# ng: rail %>\n<aside class=\"rail\"><a>x</a></aside>"))
        .to eq(%(<aside _ngcontent-rail="" class="rail"><a _ngcontent-rail="">x</a></aside>))
      expect(transform("<aside><a>x</a></aside>")).to eq("<aside><a>x</a></aside>")
    end

    it "gives a styled component's host element its _nghost attribute, after the parent's _ngcontent" do
      expect(transform("<%# ng: rail %>\n<app-avatar></app-avatar>")).to eq(%(<app-avatar _ngcontent-rail="" _nghost-avatar=""></app-avatar>))
      expect(transform("<app-status-filter></app-status-filter>")).to eq("<app-status-filter></app-status-filter>")
    end

    it "wraps a routed page in its host element" do
      expect(transform("<%# ng: pro-login %>\n<%# ng-host: pro-login %>\n<h1>x</h1>"))
        .to eq(%(<app-pro-login _nghost-pro-login=""><h1 _ngcontent-pro-login="">x</h1></app-pro-login>))
      expect(transform("<%# ng-host: clients-list %>\n<h1>x</h1>")).to eq("<app-clients-list><h1>x</h1></app-clients-list>")
    end

    it "never marks closing tags, comments or runtime output" do
      expect(transform("<%# ng: rail %>\n<!-- note --><b><%= raw \"<i>x</i>\" %></b>"))
        .to eq(%(<!-- note --><b _ngcontent-rail=""><%= raw "<i>x</i>" %></b>))
    end
  end
end
