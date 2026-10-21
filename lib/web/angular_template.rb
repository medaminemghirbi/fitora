module Web
  # Compiles the web UI's ERB the way Angular compiles its templates, so the
  # HTML that reaches the browser is the HTML the Angular app renders — not
  # merely similar markup (MIGRATION_AUDIT §5.1, §12). Two things differ
  # between the two compilers, and both show on screen:
  #
  # 1. Whitespace. Angular (preserveWhitespaces: false) drops every text node
  #    that is only whitespace and collapses runs of whitespace inside the
  #    others. ERB keeps them, and a newline between two inline elements is a
  #    visible gap. So whitespace-only text between tags is removed here, and
  #    runs inside text are collapsed, exactly as Angular's WhitespaceVisitor
  #    does — except inside <pre>, <textarea>, <script> and <style>.
  #
  # 2. Style scoping. Angular's emulated encapsulation puts _ngcontent-<id>
  #    on every element of a component's template and _nghost-<id> on its
  #    host element, and rewrites the component's CSS to require them
  #    (bin/build-css.mjs does that rewrite with Angular's own code). A
  #    template opts in with a first-line comment naming its component:
  #
  #        <%# ng: rail %>
  #
  #    and every element written in it gets _ngcontent-rail. A host element
  #    (<app-avatar>, …) of a component listed in
  #    app/assets/stylesheets/ng/manifest.json also gets _nghost-<id>.
  #    Angular does not scope a component that has no styles, and neither does
  #    this: no directive, no attributes.
  #
  #    A routed page's host element is the router's, not a parent template's,
  #    so a page template names it and is wrapped in it:
  #
  #        <%# ng-host: clients-list %>   → <app-clients-list>…</app-clients-list>
  #
  #    (with _nghost-<id> when the component has styles). The two directives
  #    can be combined, one per line.
  #
  #    A page whose Angular template has no single root, and needs one for
  #    its controller, writes its host tag itself instead of naming it: a
  #    component's template never contains its own host element, so an
  #    <app-<scope>> written in that scope's template is the host, and gets
  #    only _nghost-<scope>.
  #
  # Only literal tags in the template are touched, as in Angular: markup a
  # helper or a translation produces at runtime gets no attributes (Angular's
  # [innerHTML] content gets none either). So scoped templates write their
  # elements out instead of building them with tag helpers.
  #
  # Applies to app/views/web/** and app/views/layouts/web/** only; every other
  # template (mailers…) compiles as plain ERB.
  class AngularTemplate
    DIRECTIVE = /\A\s*<%#\s*(ng|ng-host):\s*([a-z0-9-]+)\s*%>[ \t]*\n?/

    # Angular's WS_CHARS, without the non-breaking space it deliberately keeps.
    WS = " \f\n\r\t\v ᠎ -     　﻿".freeze
    WS_ONLY = /\A[#{WS}]*\z/o
    WS_RUN = /[#{WS}]{2,}/o

    # Angular also skips <template>, which its templates never contain; the
    # web UI's <template>s hold ordinary markup the page inserts later (a
    # menu, a wizard step), which must come out exactly as it would inline.
    PRESERVE = %w[pre textarea script style].freeze

    # An output tag whose code produces elements, not text: to Angular it
    # would be an element (a child component, a link), so it bounds text
    # nodes the way a tag does. Anything else (<%= t("…") %>, a name, a
    # DatePipe or MoneyPipe result such as ng_date / ng_money) is text.
    # ng_highlight is the one ng_ helper that writes markup ([innerHTML]).
    ELEMENT_OUTPUT = /\A=\s*(render|yield|content_for|ng_highlight|link_to|button_to|form_with|tag\.|content_tag|turbo_\w+|hidden_field_tag|csrf_meta_tags|csp_meta_tag|stylesheet_link_tag|javascript_include_tag|favicon_link_tag|token_tag)\b/

    def self.erb
      @erb ||= ActionView::Template::Handlers::ERB.new
    end

    def self.call(template, source)
      return erb.call(template, source) unless applies?(template)

      erb.call(template, transform(source.dup.force_encoding(Encoding::UTF_8)))
    end

    # ActionView passes the raw source and lets the handler sort out its
    # encoding when this is true; the ERB handler does, and so must this.
    def self.handles_encoding?
      true
    end

    def self.applies?(template)
      path = template.identifier.to_s
      roots.any? { |root| path.start_with?(root) }
    end

    def self.roots
      @roots ||= [ Rails.root.join("app/views/web/").to_s, Rails.root.join("app/views/layouts/web/").to_s ]
    end

    def self.hosts
      @hosts ||= JSON.parse(Rails.root.join("app/assets/stylesheets/ng/manifest.json").read).fetch("components").keys.to_set
    end

    def self.reset!
      @hosts = nil
    end

    # Source in, source out (still ERB).
    def self.transform(source)
      scope = host = nil
      kept = +""
      while (match = source.match(DIRECTIVE))
        match[1] == "ng" ? scope = match[2] : host = match[2]
        kept << lines(match[0])
        source = source[match.end(0)..]
      end

      body = kept + new(source, scope).transform
      return body if host.nil?

      host_attr = hosts.include?(host) ? %( _nghost-#{host}="") : ""
      "<app-#{host}#{host_attr}>" + body + "</app-#{host}>"
    end

    # The newlines a removed stretch held, as an ERB comment: it prints
    # nothing, but keeps the compiled template's line numbers matching the
    # source, so an error still points at the right line.
    def self.lines(removed)
      count = removed.count("\n")
      count.zero? ? "" : "<%#" + ("\n" * count) + "%>"
    end

    def initialize(source, scope)
      @source = source
      @scope = scope
    end

    def transform
      tokens = tokenize(@source)
      out = +""
      run = [] # the tokens of the text node being collected
      preserve = nil # the tag whose content is left alone

      flush = lambda do
        unless run.empty?
          out << text_node(run)
          run = []
        end
      end

      tokens.each do |kind, value|
        if preserve
          out << (kind == :tag ? scope_tag(value) : value)
          preserve = nil if kind == :tag && closing_tag(value) == preserve
          next
        end

        case kind
        when :text, :output
          run << [ kind, value ]
        else # :tag, :control, :comment, :element_output
          flush.call
          out << (kind == :tag ? scope_tag(value) : value)
          name = opening_tag(value) if kind == :tag
          preserve = name if name && PRESERVE.include?(name) && !value.end_with?("/>")
        end
      end
      flush.call
      out
    end

    private

    # One text node: dropped when it is nothing but whitespace, otherwise
    # its literal whitespace runs collapse to one space. Output tags are kept
    # as they are — what they print is the node's dynamic part.
    def text_node(run)
      if run.none? { |kind, _| kind == :output } && run.all? { |_, value| value.match?(WS_ONLY) }
        return self.class.lines(run.map(&:last).join)
      end

      run.map { |kind, value| kind == :text ? collapse(value) : value }.join
    end

    def collapse(text)
      text.gsub(WS_RUN) { |run| " " + self.class.lines(run) }
    end

    def opening_tag(tag)
      tag[/\A<([a-zA-Z][a-zA-Z0-9-]*)/, 1]&.downcase
    end

    def closing_tag(tag)
      tag[%r{\A</([a-zA-Z][a-zA-Z0-9-]*)}, 1]&.downcase
    end

    # The scope attributes, right after the tag name, as Angular orders them.
    def scope_tag(tag)
      name = opening_tag(tag)
      return tag if name.nil?

      attrs = +""
      host = name.delete_prefix("app-")
      attrs << %( _ngcontent-#{@scope}="") if @scope && name != "app-#{@scope}"
      attrs << %( _nghost-#{host}="") if name.start_with?("app-") && self.class.hosts.include?(host)
      return tag if attrs.empty?

      tag[0, name.length + 1] + attrs + tag[(name.length + 1)..]
    end

    # ERB tags, HTML tags (which may hold ERB in their attributes) and text.
    def tokenize(source)
      tokens = []
      i = 0
      text = +""
      push_text = lambda do
        unless text.empty?
          tokens << [ :text, text ]
          text = +""
        end
      end

      while i < source.length
        if source[i, 2] == "<%"
          push_text.call
          close = source.index("%>", i + 2) or raise ArgumentError, "unclosed <% at #{i}"
          erb = source[i..close + 1]
          tokens << [ erb_kind(erb), erb ]
          i = close + 2
        elsif source[i] == "<" && source[i + 1]&.match?(%r{[a-zA-Z/!]})
          push_text.call
          close = tag_end(source, i)
          tokens << [ :tag, source[i..close] ]
          i = close + 1
        else
          text << source[i]
          i += 1
        end
      end
      push_text.call
      tokens
    end

    def erb_kind(erb)
      code = erb[2..-3]
      return :comment if code.start_with?("#")
      return :control unless code.start_with?("=")
      return :element_output if code.match?(ELEMENT_OUTPUT)

      :output
    end

    # The ">" that ends the tag starting at i — not one inside a quoted
    # attribute value or inside an ERB tag. A comment ends at "-->".
    def tag_end(source, i)
      if source[i, 4] == "<!--"
        close = source.index("-->", i + 4) or raise ArgumentError, "unclosed comment at #{i}"
        return close + 2
      end

      quote = nil
      j = i + 1
      while j < source.length
        if source[j, 2] == "<%"
          j = (source.index("%>", j + 2) or raise ArgumentError, "unclosed <% in tag at #{i}") + 2
          next
        end

        char = source[j]
        if quote
          quote = nil if char == quote
        elsif char == '"' || char == "'"
          quote = char
        elsif char == ">"
          return j
        end
        j += 1
      end
      raise ArgumentError, "unclosed tag at #{i}"
    end
  end
end
