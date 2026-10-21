# syntax=docker/dockerfile:1
# Production image for Fitora: the server-rendered web UI and the API the
# mobile app calls (/api/v1), on one origin.
# Build from this directory:  docker build -t fitora .

# ── 1. Build the web UI's bundles (jsbundling + cssbundling) ────────────
# The same scripts as `npm run build` / `build:css` in development; the
# Ruby stage then only digests what they wrote (SKIP_JS_BUILD/SKIP_CSS_BUILD).
FROM node:20-slim AS web
WORKDIR /web
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY bin/build-css.mjs ./bin/
COPY app/javascript ./app/javascript
COPY app/assets/stylesheets ./app/assets/stylesheets
RUN mkdir -p app/assets/builds && npm run build && npm run build:css
# → /web/app/assets/builds

# ── 2. Ruby base ───────────────────────────────────────────────────────
FROM registry.docker.com/library/ruby:3.4.7-slim AS base
WORKDIR /rails
ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test
RUN apt-get update -qq \
 && apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client \
 && rm -rf /var/lib/apt/lists /var/cache/apt/archives

# ── 3. Build gems ──────────────────────────────────────────────────────
FROM base AS build
RUN apt-get update -qq \
 && apt-get install --no-install-recommends -y build-essential git libpq-dev pkg-config \
 && rm -rf /var/lib/apt/lists /var/cache/apt/archives

# .ruby-version too: the Gemfile reads it (`ruby file:`), REL-07.
COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install \
 && rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git \
 && bundle exec bootsnap precompile --gemfile

COPY . .
RUN bundle exec bootsnap precompile app/ lib/

# The web UI's assets, digested into public/assets. The icon font is read
# from node_modules (config.assets.paths), as in development. A build has
# none of the runtime settings (required_env.rb): they are checked at boot.
COPY --from=web /web/app/assets/builds ./app/assets/builds
COPY --from=web /web/node_modules/bootstrap-icons/font ./node_modules/bootstrap-icons/font
RUN SECRET_KEY_BASE_DUMMY=1 SKIP_REQUIRED_ENV_CHECK=1 SKIP_JS_BUILD=1 SKIP_CSS_BUILD=1 ./bin/rails assets:precompile \
 && rm -rf node_modules

# ── 4. Final image ─────────────────────────────────────────────────────
FROM base
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Run as an unprivileged user.
RUN groupadd --system --gid 1000 rails \
 && useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash \
 && chown -R rails:rails db log storage tmp
USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["./bin/rails", "server"]
