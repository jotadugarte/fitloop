# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper, "[REQ-FIT-UI-001]", type: :helper do
  describe "#render_markdown" do
    it "returns an empty string for blank input" do
      expect(helper.render_markdown(nil)).to eq("")
      expect(helper.render_markdown("")).to eq("")
    end

    it "renders markdown to safe HTML" do
      html = helper.render_markdown("**bold**")

      expect(html).to include("<strong>bold</strong>")
      expect(html).to be_html_safe
    end
  end

  describe "auth navigation helpers" do
    it "uses the stored workspace return path when present" do
      helper.session[:workspace_return_to] = "/taller"

      expect(helper.auth_back_path).to eq("/taller")
      expect(helper.auth_back_label).to eq(I18n.t("auth.nav.back"))
    end

    it "falls back to home when no return path is stored" do
      expect(helper.auth_back_path).to eq(helper.root_path)
      expect(helper.auth_back_label).to eq(I18n.t("auth.nav.home"))
    end
  end

  describe "#layout_flash_messages" do
    it "keeps alerts on non-session pages" do
      flash[:alert] = "notice me"

      expect(helper.layout_flash_messages).to include("alert" => "notice me")
    end

    it "suppresses alerts on the sign-in page" do
      allow(helper).to receive(:devise_controller?).and_return(true)
      allow(helper).to receive(:controller_name).and_return("sessions")
      flash[:alert] = "hidden on sign-in"
      flash[:notice] = "still visible"

      expect(helper.layout_flash_messages).to eq("notice" => "still visible")
    end
  end

  describe "workspace tab helpers" do
    it "prefers the request header tab id" do
      helper.request.headers[ResolvesWorkspaceTab::TAB_HEADER] = "header-tab"
      helper.request.cookies[ResolvesWorkspaceTab::TAB_COOKIE] = "cookie-tab"

      expect(helper.workspace_tab_id_from_request).to eq("header-tab")
    end

    it "falls back to the workspace tab cookie" do
      helper.request.headers[ResolvesWorkspaceTab::TAB_HEADER] = nil
      helper.request.cookies[ResolvesWorkspaceTab::TAB_COOKIE] = "cookie-tab"

      expect(helper.workspace_tab_id_from_request).to eq("cookie-tab")
    end

    it "falls back to the default tab id" do
      helper.request.headers[ResolvesWorkspaceTab::TAB_HEADER] = nil
      helper.request.cookies[ResolvesWorkspaceTab::TAB_COOKIE] = nil

      expect(helper.workspace_tab_id_from_request).to eq(Workspace::DEFAULT_TAB_ID)
    end

    it "returns the sole bound tab id for the client" do
      helper.session[Workspace::WORKSPACES_KEY] = { "only-tab" => 42 }

      expect(helper.workspace_tab_id_for_client).to eq("only-tab")
    end

    it "returns nil when multiple workspace tabs are bound" do
      helper.session[Workspace::WORKSPACES_KEY] = { "a" => 1, "b" => 2 }

      expect(helper.workspace_tab_id_for_client).to be_nil
    end

    it "rebinds the toolbar project when the request tab differs" do
      project = ProjectSpecFactory.create!(title: "Toolbar bind")
      helper.session[Workspace::WORKSPACES_KEY] = { "stored-tab" => project.id }
      helper.request.headers[ResolvesWorkspaceTab::TAB_HEADER] = "request-tab"

      expect(Workspace).to receive(:bind!).with(helper.session, project, tab_id: "request-tab")

      helper.toolbar_workspace_project
    end
  end

  describe "workshop helpers" do
    let(:project) { ProjectSpecFactory.create!(title: "Workshop helper") }

    it "builds workshop UX mode and paths" do
      expect(helper.workshop_ux_mode(project)).to be_a(Workshop::UxMode)
      expect(helper.toolbar_workshop_path).to eq(helper.workshop_path)
      expect(helper.toolbar_workshop_button_class).to include("toolbar-workshop__btn")
    end

    it "returns nil checkout lock helpers when no warden user is available" do
      allow(helper).to receive(:warden_user_if_available).and_return(nil)

      expect(helper.pending_checkout_lock(project)).to be_nil
      expect(helper.workshop_mutations_locked?(project)).to be_nil
    end

    it "resolves pending checkout lock for the signed-in user" do
      user = instance_double(User, id: 42)
      lock = instance_double(Billing::PendingCheckoutLock, active?: true)
      allow(helper).to receive(:warden_user_if_available).and_return(user)
      allow(Billing::PendingCheckoutLock).to receive(:for).with(project: project, user: user).and_return(lock)

      expect(helper.pending_checkout_lock(project)).to eq(lock)
      expect(helper.workshop_mutations_locked?(project)).to be(true)
    end

    it "returns nil from warden_user_if_available when Warden is missing" do
      warden = instance_double(Warden::Proxy)
      allow(warden).to receive(:user).and_raise(Devise::MissingWarden)
      allow(helper).to receive(:request).and_return(instance_double(ActionDispatch::Request, env: { "warden" => warden }))

      expect(helper.send(:warden_user_if_available)).to be_nil
    end

    it "returns nil when the request env lacks Warden" do
      allow(helper).to receive(:request).and_return(instance_double(ActionDispatch::Request, env: {}))

      expect(helper.send(:warden_user_if_available)).to be_nil
    end

    it "returns nil when Warden has no authenticated user" do
      warden = instance_double(Warden::Proxy, user: nil)
      allow(helper).to receive(:request).and_return(instance_double(ActionDispatch::Request, env: { "warden" => warden }))

      expect(helper.send(:warden_user_if_available)).to be_nil
    end
  end

  describe "account and sheet helpers" do
    it "formats nesting values and sheet summaries" do
      stock = SheetStock.new(width_mm: 1000, height_mm: 2000, quantity: nil, sort_order: 0)

      expect(helper.nesting_mm_value(2.5)).to eq(I18n.t("projects.show.nesting_value_mm", value: "2.5"))
      expect(helper.sheet_stock_quantity_label(stock)).to eq(I18n.t("projects.form.quantity_unlimited"))
      expect(helper.sheet_stock_consumption_priority_label(stock)).to eq("#1")
      expect(helper.sheet_stock_summary(stock)).to include("1000", "2000", I18n.t("projects.form.quantity_unlimited"))
    end

    it "maps unknown admin event types through i18n with a default label" do
      expect(helper.event_label("workspace_started")).to eq(I18n.t("admin.events.workspace_started"))
      expect(helper.event_label("custom_event")).to eq("Custom event")
    end

    it "returns password hints and account error copy" do
      user = User.new
      user.errors.add(:current_password, :invalid)
      expect(helper.account_current_password_error_message(user)).to eq(I18n.t("auth.account.current_password_invalid"))

      user = User.new
      user.errors.add(:current_password, "must match")
      expect(helper.account_current_password_error_message(user))
        .to eq(user.errors.full_messages_for(:current_password).first)

      expect(helper.account_password_section_open?(user)).to be(true)
      expect(helper.password_validation_form_data(optional: true)[:controller]).to eq("password-validation")
      expect(helper.auth_password_length_hint).to include(Devise.password_length.begin.to_s)
    end
  end
end
