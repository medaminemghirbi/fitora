require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # The Sidekiq dashboard. Open in development; HTTP basic auth everywhere
  # else, and only mounted at all once SIDEKIQ_WEB_PASSWORD is set.
  unless Rails.env.development?
    Sidekiq::Web.use Rack::Auth::Basic do |user, password|
      expected_user = ENV.fetch("SIDEKIQ_WEB_USER", "fitora")
      expected_pass = ENV["SIDEKIQ_WEB_PASSWORD"].to_s
      expected_pass.present? &&
        ActiveSupport::SecurityUtils.secure_compare(::Digest::SHA256.hexdigest(user), ::Digest::SHA256.hexdigest(expected_user)) &
        ActiveSupport::SecurityUtils.secure_compare(::Digest::SHA256.hexdigest(password), ::Digest::SHA256.hexdigest(expected_pass))
    end
  end
  mount Sidekiq::Web => "/sidekiq" if Rails.env.development? || ENV["SIDEKIQ_WEB_PASSWORD"].present?

  namespace :api do
    namespace :v1 do
      post "auth/register", to: "auth#register"
      post "auth/login", to: "auth#login"
      post "auth/logout", to: "auth#logout"
      patch "auth/password", to: "auth#change_password"
      get "auth/me", to: "auth#me"
      get "me/permissions", to: "auth#permissions"
      get "bootstrap", to: "bootstrap#show"
      # A 30-second, single-use pass for opening /cable — see JwtService.
      post "cable_ticket", to: "auth#cable_ticket"
      get "app_version", to: "app_version#show"

      # Account recovery / email confirmation (token in the URL, unauthenticated)
      resources :email_verifications, only: [ :create, :update ], param: :token
      resources :password_resets, only: [ :create, :update ], param: :token
      resources :invitations, only: [ :update ], param: :token

      resources :notifications, only: [ :index, :show ] do
        member { patch :read }
        collection do
          post :read_all
          get :unread_count
        end
      end

      resource :company, only: [ :show, :update ]
      # Plural: an admin runs as many salles as they like — :show/:update
      # above always act on whichever one is currently active; these
      # list/create/switch between them, and post moderators to them.
      resources :companies, only: [ :index, :create ] do
        member do
          post :switch
          put :moderators, to: "companies#update_moderators"
        end
        collection { get :network }
      end
      get "branding", to: "branding#show"
      # The mobile app's keys (Settings → Application mobile, Pro) and the
      # public lookup the app makes with one of them before signing in.
      get "mobile_app", to: "mobile_app#show"
      post "mobile_app/regenerate", to: "mobile_app#regenerate"
      get "tenants/:code/app_config", to: "tenants#app_config"

      # Resumable first-time setup. Singular: there is one flow per company.
      resource :onboarding, only: [ :show, :update ], controller: "onboarding" do
        post :skip
        post :dismiss
      end
      # except: the API never had new/edit forms (it was api_only until the
      # web UI arrived); the route set stays exactly what it was.
      resources :activities, except: %i[new edit] do
        collection { post :adopt }
      end
      # The platform's catalogue a salle picks its activities from — readable
      # before the salle exists, at signup.
      resources :activity_templates, only: [ :index ]
      resources :spaces, except: %i[new edit]
      resources :coaches, except: %i[new edit] do
        member do
          post :login, to: "coaches#set_login"
        end
      end
      resources :sessions, only: [ :index, :show, :create, :update ] do
        collection do
          get :schedule_pdf
        end
        member do
          post :cancel
        end
      end
      resources :bookings, only: [ :index, :show, :create ] do
        member do
          post :cancel
        end
      end
      resources :clients, only: [ :index, :show, :create, :update, :destroy ] do
        member { post :invite }
      end

      get "data_exchange/:entity/template", to: "data_exchange#template"
      get "data_exchange/:entity/export", to: "data_exchange#export"
      post "data_exchange/:entity/import", to: "data_exchange#import"
      get "data_exchange/imports/:id", to: "data_exchange#show_import"

      get "subscription", to: "subscription#show"
      # The gym's own invoices; :show is the PDF.
      resources :invoices, only: [ :index, :show ]

      resources :contract_types, only: [ :index, :show, :create, :update ]
      resources :packs, only: [ :index, :create, :update, :destroy ]
      resources :contracts, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :renew
          post :cancel
          post :pause
          post :resume
          get :receipt
          get :agreement
        end
      end
      resources :payments, only: [ :index, :show, :create ] do
        member do
          post :refund
        end
      end

      resources :staff, only: [ :index, :show, :create, :update ]
      resources :roles, only: [ :index, :create, :update, :destroy ]

      resources :attendance, only: [ :index, :create ]
      resources :recurring_schedules, only: [ :index, :create, :update ]
      resources :audit_logs, only: [ :index ]
      resources :app_updates, only: [ :index ]
      resources :support_tickets, only: [ :index, :create ] do
        member do
          get "attachments/:attachment_id", action: :attachment, as: :attachment
        end
      end

      # A member's own app: their gym's schedule, their bookings, their file.
      # No directory and no self-signup — the gym enables the account from
      # the member's own record (Api::V1::ClientsController#update).
      namespace :me do
        resource :profile, only: [ :show, :update ]
        # Leaving Fitora altogether — see Client#anonymise!.
        resource :account, only: [ :destroy ]
        resources :notifications, only: [ :index, :show ] do
          member { patch :read }
          collection do
            post :read_all
            get :unread_count
          end
        end
        resources :sessions, only: [ :index ]
        resources :bookings, only: [ :index, :create ] do
          member { post :cancel }
        end
      end

      # A coach's own day. Only what no existing endpoint already answers:
      # the schedule and attendance controllers narrow to a coach's own
      # sessions themselves, and a second route to the same data would be a
      # second place for that narrowing to be got wrong.
      namespace :coach do
        resources :members, only: [ :index ]
      end

      namespace :admin do
        get "dashboard", to: "dashboard#show"
        get "revenue", to: "revenue#show"
        get "reports/export", to: "reports#export"
      end

      namespace :superadmin do
        resources :companies, only: [ :index, :show ] do
          member do
            patch :subscription, to: "companies#update_subscription"
            patch :settings, to: "companies#update_settings"
            post :impersonate, to: "companies#impersonate"
            get :invoices, to: "companies#invoices"
            post :invoices, to: "companies#create_invoice"
            delete "invoices/:invoice_id", to: "companies#destroy_invoice", as: :invoice
          end
        end
        get "metrics", to: "metrics#show"
        get "subscription_pricing", to: "subscription_pricing#show"
        patch "subscription_pricing", to: "subscription_pricing#update"
        resources :app_updates, only: [ :index, :create ]
        resources :support_tickets, only: [ :index ] do
          member do
            patch :resolve
            get "attachments/:attachment_id", action: :attachment, as: :attachment
          end
        end
      end
    end
  end

  # ---- The server-rendered web UI (MIGRATION_AUDIT_2026-10-15.md §8) ----
  # What every shell shares: signing out and the language.
  scope module: :web do
    delete "deconnexion", to: "sessions#destroy", as: :web_sign_out
    patch "locale", to: "locales#update", as: :web_locale
  end

  scope module: :web do
    get "connexion", to: "sessions#new", as: :web_sign_in
    post "connexion", to: "sessions#create"

    # The account pages (module 1).
    get "inscription", to: "registrations#new"
    post "inscription", to: "registrations#create"
    get "mot-de-passe-oublie", to: "password_resets#new"
    post "mot-de-passe-oublie", to: "password_resets#create"
    get "auth/reset-password", to: "password_resets#edit"
    patch "auth/reset-password", to: "password_resets#update"
    get "auth/accept-invitation", to: "invitations#edit"
    patch "auth/accept-invitation", to: "invitations#update"
    get "verify-email", to: "email_verifications#show"
    patch "verify-email", to: "email_verifications#update"
    get "confirmation-email", to: "confirmations#show"
    get "confirmation-email/status", to: "confirmations#status"
    post "confirmation-email/resend", to: "confirmations#resend"
    get "account-locked", to: "account_locks#show"

    # The first salle (module 4).
    get "admin/setup-company", to: "company_setups#show", as: :web_company_setup
    post "admin/setup-company", to: "company_setups#create"
    # The landing page (module 11).
    get "/", to: "landing#show", as: :web_landing, format: false
    # Where the earlier layouts put these (app.routes.ts), with the query
    # kept as redirectTo keeps it.
    {
      "trial-expired" => "/account-locked", "pro" => "/", "pro/connexion" => "/connexion",
      "pro/mot-de-passe-oublie" => "/mot-de-passe-oublie", "auth/login" => "/connexion",
      "auth/register" => "/inscription", "auth/forgot-password" => "/mot-de-passe-oublie"
    }.each do |old_path, to|
      get old_path, format: false, to: redirect(status: 302) { |_, req| [ to, req.query_string.presence ].compact.join("?") }
    end
    # A gym is joined, never found: the old directory goes to the landing page.
    get "gyms(/*rest)", to: redirect("/", status: 302), format: false

    # The admin shell, in the salle the URL names (§8.1).
    scope "admin/:salle_id", module: :admin, as: :web_admin, constraints: { salle_id: Web::Routing::SALLE } do
      get "clients", to: "clients#index", as: :clients
      post "clients", to: "clients#create"
      post "email_verification", to: "email_verifications#create", as: :email_verification
      post "switch/:id", to: "salles#switch", as: :switch_salle
      get "salles", to: "salles#network", as: :salles
      post "salles", to: "salles#create"
      put "salles/:id/moderators", to: "salles#update_moderators"
      # Module 2.
      get "updates", to: "updates#index", as: :updates
      get "notifications", to: "notifications#index", as: :notifications
      post "notifications/read_all", to: "notifications#read_all"
      get "notifications/:id", to: "notifications#show", as: :notification
      patch "notifications/:id/read", to: "notifications#read"
      get "support", to: "support#index", as: :support
      post "support", to: "support#create"
      get "support/:id/attachments/:attachment_id", to: "support#attachment", as: :support_attachment
      resources :spaces, only: %i[index create update destroy]
      resources :bookings, only: :index do
        member do
          post :cancel
        end
      end
      # Module 3.
      resources :contracts, only: :index do
        member do
          post :renew
          post :pause
          post :resume
          post :collect
          get :agreement
          get :receipt
        end
      end
      # The plan and activity lists moved into the catalogue (admin.routes.ts).
      # A 302 with the query kept, as redirectTo keeps it (and a rollback
      # leaves no cached 301 behind, §9.4).
      %w[plans activities].each do |old_list|
        get "contracts/#{old_list}", to: redirect(status: 302) { |p, req|
          [ "/admin/#{p[:salle_id]}/catalogue", req.query_string.presence ].compact.join("?")
        }
      end
      resources :payments, only: %i[index create] do
        post :refund, on: :member
        collection do
          get :clients
          get :payables
        end
      end
      # Module 4.
      scope "catalogue", controller: :catalogue do
        get "/", action: :show, as: :catalogue
        post "activities", action: :create_activity
        post "activities/adopt", action: :adopt
        patch "activities/:id", action: :update_activity
        delete "activities/:id", action: :deactivate_activity
        post "plans", action: :create_plan
        patch "plans/:id", action: :update_plan
        post "packs", action: :create_pack
        patch "packs/:id", action: :update_pack
        delete "packs/:id", action: :deactivate_pack
      end
      get "onboarding", to: "onboarding#show", as: :onboarding
      post "onboarding/complete", to: "onboarding#complete"
      post "onboarding/skip", to: "onboarding#skip"
      post "onboarding/dismiss", to: "onboarding#dismiss"
      get "getting-started", to: redirect(status: 302) { |p, _| "/admin/#{p[:salle_id]}/onboarding" }
      # Module 5.
      scope "team", controller: :team do
        get "/", action: :index, as: :team
        post "coaches", action: :create_coach
        get "coaches/:id", action: :show_coach
        patch "coaches/:id", action: :update_coach
        delete "coaches/:id", action: :deactivate_coach
        post "coaches/:id/login", action: :set_login
        post "staff", action: :create_staff
        patch "staff/:id", action: :update_staff
      end
      # Coaches and staff became one page (admin.routes.ts).
      %w[coaches staff].each do |old_list|
        get old_list, to: redirect(status: 302) { |p, req|
          [ "/admin/#{p[:salle_id]}/team", req.query_string.presence ].compact.join("?")
        }
      end
      # Module 6.
      scope "settings", controller: :settings do
        get "/", action: :show, as: :settings
        patch "company", action: :update_company
        patch "password", action: :update_password
        post "sign-out-everywhere", action: :sign_out_everywhere
        post "roles", action: :create_role
        patch "roles/:id", action: :update_role
        delete "roles/:id", action: :destroy_role
        post "mobile-app/regenerate", action: :regenerate_key
        get "data-exchange/imports/:id", action: :show_import
        get "data-exchange/:entity/template", action: :data_template
        get "data-exchange/:entity/export", action: :export_data
        post "data-exchange/:entity/import", action: :import_data
        get ":section", action: :show, as: :settings_section
      end
      get "subscription", to: "subscription#show", as: :subscription
      get "invoices/:id", to: "invoices#show", as: :invoice
      post "subscription/request", to: "subscription#request_plan"
      # The marketplace is gone (admin.routes.ts).
      get "modules", to: redirect(status: 302) { |p, _| "/admin/#{p[:salle_id]}/subscription" }
      # Import/export moved under Settings (admin.routes.ts).
      get "data-exchange", to: redirect(status: 302) { |p, _| "/admin/#{p[:salle_id]}/settings/data-exchange" }
      # Module 8.
      scope "clients/:id", controller: :client_profiles, constraints: { id: Web::Routing::SALLE } do
        get "/", action: :show, as: :client
        patch "/", action: :update
        delete "/", action: :destroy
        post "invite", action: :invite
        post "contracts", action: :sell
        post "bookings", action: :book
        get "sessions", action: :sessions
      end
      # Module 7.
      get "dashboard", to: "dashboard#show", as: :dashboard
      get "dashboard/report", to: "dashboard#report"
      get "attendance/:session_id", to: "attendance#show", as: :attendance
      post "attendance", to: "attendance#create"
      # Module 9.
      scope "calendar", controller: :calendar do
        get "/", action: :show, as: :calendar
        get "events", action: :events
        get "clients", action: :clients
        get "schedule", action: :schedule_pdf
        post "sessions", action: :create
        patch "sessions/:id", action: :move
        post "sessions/:id/cancel", action: :cancel
        post "sessions/:id/bookings", action: :book
        patch "series/:id", action: :stop_series
      end
      # The command palette's search (⌘K).
      get "palette", to: "palette#search"
      # The shell's own address: Angular's "" → dashboard, in this salle.
      get "/", to: redirect(status: 302) { |p, _| "/admin/#{p[:salle_id]}/dashboard" }
      # Anything else: Angular's `**` → "" (app.routes.ts).
      get "*page", to: redirect("/", status: 302), format: false
    end

    # Pre-migration admin URLs → the same page in the current salle (§8.3).
    get "admin(/*path)", to: "legacy#show", defaults: { shell: "admin" }, format: false
  end

  # ---- The front desk (module 10) ----
  scope "desk/:salle_id", module: "web/desk", as: :web_desk, constraints: { salle_id: Web::Routing::SALLE } do
    get "dashboard", to: "dashboard#show", as: :dashboard
    get "checkin", to: "checkin#show", as: :checkin
    get "clients", to: "clients#index"
    get "attendance/:session_id", to: "attendance#show"
    post "attendance", to: "attendance#create"
    post "switch/:id", to: "salles#switch"
    get "/", to: redirect(status: 302) { |p, _| "/desk/#{p[:salle_id]}/dashboard" }
    get "*page", to: redirect("/", status: 302), format: false
  end
  get "desk(/*path)", to: "web/legacy#show", defaults: { shell: "desk" }, format: false

  # ---- A coach's day (module 10) ----
  scope "coach/:salle_id", module: "web/coach", as: :web_coach, constraints: { salle_id: Web::Routing::SALLE } do
    get "today", to: "today#show", as: :today
    get "members", to: "members#index", as: :members
    get "attendance/:session_id", to: "attendance#show"
    post "attendance", to: "attendance#create"
    get "/", to: redirect(status: 302) { |p, _| "/coach/#{p[:salle_id]}/today" }
    get "*page", to: redirect("/", status: 302), format: false
  end
  get "coach(/*path)", to: "web/legacy#show", defaults: { shell: "coach" }, format: false

  # ---- A member's own app (module 10): its Angular URLs (§8.1) ----
  scope "member", module: "web/member", as: :web_member do
    get "home", to: "schedule#show", as: :home
    get "bookings", to: "bookings#index", as: :bookings
    post "bookings", to: "bookings#create"
    post "bookings/:id/cancel", to: "bookings#cancel"
    get "profile", to: "profile#show", as: :profile
    patch "profile", to: "profile#update"
    patch "password", to: "profile#update_password"
    post "sign-out-everywhere", to: "profile#sign_out_everywhere"
    delete "account", to: "profile#destroy"
    post "gym", to: "profile#switch_gym"
    get "notifications", to: "notifications#index"
    post "notifications/read_all", to: "notifications#read_all"
    patch "notifications/:id/read", to: "notifications#read"
    get "/", to: redirect("/member/home", status: 302)
    # Anything else: Angular's `**` → "" (app.routes.ts).
    get "*page", to: redirect("/", status: 302), format: false
  end

  # ---- The superadmin's console (module 10): its Angular URLs (§8.1), and
  # what it has grown since: the invoices, a page per ticket and release ----
  scope "superadmin", module: "web/superadmin", as: :web_superadmin do
    get "overview", to: "overview#show", as: :overview
    get "companies", to: "companies#index", as: :companies
    get "companies/:id", to: "companies#show", as: :company
    patch "companies/:id/subscription", to: "companies#update_subscription"
    patch "companies/:id/settings", to: "companies#update_settings"
    post "companies/:id/impersonate", to: "companies#impersonate"
    post "companies/:id/invoices", to: "companies#create_invoice"
    delete "companies/:id/invoices/:invoice_id", to: "companies#destroy_invoice"
    get "invoices", to: "invoices#index", as: :invoices
    get "invoices/:id/pdf", to: "invoices#pdf", as: :invoice_pdf
    get "pricing", to: "pricing#show", as: :pricing
    patch "pricing", to: "pricing#update"
    post "pricing/rates", to: "pricing#refresh_rates"
    get "billing", to: "billing#show", as: :billing
    patch "billing", to: "billing#update"
    get "support", to: "support#index", as: :support
    get "support/:id", to: "support#show", as: :support_ticket
    patch "support/:id/resolve", to: "support#resolve"
    get "support/:id/attachments/:attachment_id", to: "support#attachment", as: :support_attachment
    get "updates", to: "updates#index", as: :updates
    post "updates", to: "updates#create"
    get "updates/:id", to: "updates#show", as: :update
    get "notifications", to: "notifications#index"
    post "notifications/read_all", to: "notifications#read_all"
    patch "notifications/:id/read", to: "notifications#read"
    # The marketplace is gone (superadmin.routes): its prices are here.
    get "modules", to: redirect("/superadmin/pricing", status: 302)
    get "/", to: redirect("/superadmin/overview", status: 302)
    # Anything else: Angular's `**` → "" (app.routes.ts).
    get "*page", to: redirect("/", status: 302), format: false
  end

  # Any other page: Angular's `**` → "" (app.routes.ts). Must stay last.
  get "*path", to: redirect("/", status: 302), format: false, constraints: ->(req) {
    req.get? && req.format.html? &&
      %w[/api /cable /rails /up /sidekiq /assets].none? { |p| req.path.start_with?(p) }
  }
end
