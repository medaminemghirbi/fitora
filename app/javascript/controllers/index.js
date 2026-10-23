import { Application } from "@hotwired/stimulus"

import FormChecksController from "./form_checks_controller"
import NavbarController from "./navbar_controller"
import ToastsController from "./toasts_controller"
import ModalController from "./modal_controller"
import ClientsListController from "./clients_list_controller"
import ClientWizardController from "./client_wizard_controller"
import EmailBannerController from "./email_banner_controller"
import LocaleSwitchController from "./locale_switch_controller"
import NewPasswordController from "./new_password_controller"
import RedirectController from "./redirect_controller"
import SetupProgressController from "./setup_progress_controller"
import VerifyEmailController from "./verify_email_controller"
import ConfirmEmailController from "./confirm_email_controller"
import FormSubmitController from "./form_submit_controller"
import NotificationsInboxController from "./notifications_inbox_controller"
import NotificationBellController from "./notification_bell_controller"
import SupportFormController from "./support_form_controller"
import ActionMenuController from "./action_menu_controller"
import ClientListController from "./client_list_controller"
import SpacesPageController from "./spaces_page_controller"
import FilterRailController from "./filter_rail_controller"
import BookingsListController from "./bookings_list_controller"
import ContractsListController from "./contracts_list_controller"
import PaymentsListController from "./payments_list_controller"
import CatalogueController from "./catalogue_controller"
import OnboardingController from "./onboarding_controller"
import ActivityPickerController from "./activity_picker_controller"
import SearchableSelectController from "./searchable_select_controller"
import CompanySetupController from "./company_setup_controller"
import TeamPageController from "./team_page_controller"
import SallesPageController from "./salles_page_controller"
import SettingsShellController from "./settings_shell_controller"
import SettingsCompanyController from "./settings_company_controller"
import SettingsPlanningController from "./settings_planning_controller"
import SettingsBookingController from "./settings_booking_controller"
import SettingsBrandingController from "./settings_branding_controller"
import SignaturePadController from "./signature_pad_controller"
import SettingsRolesController from "./settings_roles_controller"
import SettingsMobileAppController from "./settings_mobile_app_controller"
import ThemeSwitchController from "./theme_switch_controller"
import ChangePasswordController from "./change_password_controller"
import DataExchangeController from "./data_exchange_controller"
import SubscriptionPageController from "./subscription_page_controller"
import SubscriptionsController from "./subscriptions_controller"
import CheckinPanelController from "./checkin_panel_controller"
import DashboardPageController from "./dashboard_page_controller"
import ClientProfileController from "./client_profile_controller"
import PageReloadController from "./page_reload_controller"
import CalendarPageController from "./calendar_page_controller"
import ShellMenuController from "./shell_menu_controller"
import DeskSearchController from "./desk_search_controller"
import DeskCheckinController from "./desk_checkin_controller"
import CoachTodayController from "./coach_today_controller"
import CoachMembersController from "./coach_members_controller"
import MemberScheduleController from "./member_schedule_controller"
import MemberBookingsController from "./member_bookings_controller"
import MemberProfileController from "./member_profile_controller"
import DataTableController from "./data_table_controller"
import CopyController from "./copy_controller"
import SuperadminCompanyController from "./superadmin_company_controller"
import SuperadminPricingController from "./superadmin_pricing_controller"
import SuperadminUpdatesController from "./superadmin_updates_controller"
import LandingController from "./landing_controller"
import CommandPaletteController from "./command_palette_controller"

const application = Application.start()
application.register("form-checks", FormChecksController)
application.register("navbar", NavbarController)
application.register("toasts", ToastsController)
application.register("modal", ModalController)
application.register("clients-list", ClientsListController)
application.register("client-wizard", ClientWizardController)
application.register("email-banner", EmailBannerController)
application.register("locale-switch", LocaleSwitchController)
application.register("new-password", NewPasswordController)
application.register("redirect", RedirectController)
application.register("setup-progress", SetupProgressController)
application.register("verify-email", VerifyEmailController)
application.register("confirm-email", ConfirmEmailController)
application.register("form-submit", FormSubmitController)
application.register("notifications-inbox", NotificationsInboxController)
application.register("notification-bell", NotificationBellController)
application.register("support-form", SupportFormController)
application.register("action-menu", ActionMenuController)
application.register("client-list", ClientListController)
application.register("spaces-page", SpacesPageController)
application.register("filter-rail", FilterRailController)
application.register("bookings-list", BookingsListController)
application.register("contracts-list", ContractsListController)
application.register("payments-list", PaymentsListController)
application.register("catalogue", CatalogueController)
application.register("onboarding", OnboardingController)
application.register("activity-picker", ActivityPickerController)
application.register("searchable-select", SearchableSelectController)
application.register("company-setup", CompanySetupController)
application.register("team-page", TeamPageController)
application.register("salles-page", SallesPageController)
application.register("settings-shell", SettingsShellController)
application.register("settings-company", SettingsCompanyController)
application.register("settings-planning", SettingsPlanningController)
application.register("settings-booking", SettingsBookingController)
application.register("settings-branding", SettingsBrandingController)
application.register("signature-pad", SignaturePadController)
application.register("settings-roles", SettingsRolesController)
application.register("settings-mobile-app", SettingsMobileAppController)
application.register("theme-switch", ThemeSwitchController)
application.register("change-password", ChangePasswordController)
application.register("data-exchange", DataExchangeController)
application.register("subscription-page", SubscriptionPageController)
application.register("subscriptions", SubscriptionsController)
application.register("checkin-panel", CheckinPanelController)
application.register("dashboard-page", DashboardPageController)
application.register("client-profile", ClientProfileController)
application.register("page-reload", PageReloadController)
application.register("calendar-page", CalendarPageController)
application.register("shell-menu", ShellMenuController)
application.register("desk-search", DeskSearchController)
application.register("desk-checkin", DeskCheckinController)
application.register("coach-today", CoachTodayController)
application.register("coach-members", CoachMembersController)
application.register("member-schedule", MemberScheduleController)
application.register("member-bookings", MemberBookingsController)
application.register("member-profile", MemberProfileController)
application.register("data-table", DataTableController)
application.register("copy", CopyController)
application.register("superadmin-company", SuperadminCompanyController)
application.register("superadmin-pricing", SuperadminPricingController)
application.register("superadmin-updates", SuperadminUpdatesController)
application.register("landing", LandingController)
application.register("command-palette", CommandPaletteController)
