module ApplicationHelper
  include WorkshopUrlHelper
  include NestingProgressHelper
  include UiHelper
  include NestingPreviewHelper

  def render_markdown(text)
    return "" if text.blank?

    renderer = Redcarpet::Render::HTML.new(hard_wrap: true)
    markdown = Redcarpet::Markdown.new(renderer, autolink: true)
    markdown.render(text).html_safe
  end



  def auth_back_path
    session[:workspace_return_to].presence || root_path
  end

  def auth_back_label
    session[:workspace_return_to].present? ? t("auth.nav.back") : t("auth.nav.home")
  end

  def layout_flash_messages
    return flash.to_hash unless suppress_sign_in_alert_in_layout?

    flash.to_hash.except("alert", :alert)
  end

  def suppress_sign_in_alert_in_layout?
    devise_controller? && controller_name == "sessions"
  end

  def workspace_tab_id_from_request
    request.headers[ResolvesWorkspaceTab::TAB_HEADER].presence ||
      cookies[ResolvesWorkspaceTab::TAB_COOKIE].presence ||
      Workspace::DEFAULT_TAB_ID
  end

  def workspace_tab_id_for_client
    hash = session[Workspace::WORKSPACES_KEY].to_h
    return nil unless hash.size == 1

    hash.keys.first
  end

  def toolbar_workspace_project
    @toolbar_workspace_project ||= begin
      tid = workspace_tab_id_from_request
      project = Workspace.any_bound_project(session, prefer_tab_id: tid)
      if project && Workspace.tab_id_for_project(session, project.id) != tid
        Workspace.bind!(session, project, tab_id: tid)
      end
      project
    end
  end

  def toolbar_workshop_path
    workshop_path
  end

  def workshop_ux_mode(project)
    Workshop::UxMode.new(project)
  end

  def pending_checkout_lock(project)
    user = warden_user_if_available
    return nil unless user

    Billing::PendingCheckoutLock.for(project: project, user: user)
  end

  def workshop_mutations_locked?(project)
    pending_checkout_lock(project)&.active?
  end

  # Turbo Stream broadcasts render partials without the Warden middleware stack.
  def warden_user_if_available
    env = request&.env
    return nil unless env&.key?("warden")

    env["warden"]&.user
  rescue Devise::MissingWarden
    nil
  end
  private :warden_user_if_available

  def toolbar_workshop_button_class
    # /taller auto-creates an ephemeral project when unbound; always treat as primary nav.
    "btn btn--compact toolbar-workshop__btn btn-primary"
  end

  def auth_password_length_hint
    t("auth.password.length_hint", min: Devise.password_length.begin)
  end

  def account_current_password_error_message(user)
    return t("auth.account.current_password_invalid") if user.errors.of_kind?(:current_password, :invalid)

    user.errors.full_messages_for(:current_password).first
  end

  def account_password_section_open?(user)
    %i[current_password password password_confirmation].any? { |attr| user.errors.include?(attr) }
  end

  def password_validation_form_data(optional: false)
    min = Devise.password_length.begin
    {
      controller: "password-validation",
      password_validation_min_value: min,
      password_validation_optional_value: optional,
      password_validation_too_short_value: t("auth.password.validation.too_short", min: min),
      password_validation_mismatch_value: t("auth.password.validation.mismatch"),
      password_validation_match_value: t("auth.password.validation.match")
    }
  end

  def sheet_stock_dimension_mm(value)
    number_with_precision(value, precision: 1, strip_insignificant_zeros: true)
  end

  def nesting_mm_value(value)
    formatted = number_with_precision(value, precision: 2, strip_insignificant_zeros: true)
    t("projects.show.nesting_value_mm", value: formatted)
  end

  def sheet_stock_quantity_label(stock)
    stock.quantity.present? ? stock.quantity.to_s : t("projects.form.quantity_unlimited")
  end

  def sheet_stock_consumption_priority_label(stock)
    "##{stock.sort_order.to_i + 1}"
  end

  def sheet_stock_summary(stock)
    t(
      "projects.form.sheet_summary",
      width: sheet_stock_dimension_mm(stock.width_mm),
      height: sheet_stock_dimension_mm(stock.height_mm),
      quantity: sheet_stock_quantity_label(stock)
    )
  end

  def event_label(event_type)
    t("admin.events.#{event_type}", default: event_type.to_s.humanize)
  end

  def discord_invite_url
    ENV.fetch("DISCORD_INVITE_URL", "https://discord.gg/modusloop")
  end

  def feedback_fab_visible?
    !controller_path.start_with?("admin/")
  end
end
