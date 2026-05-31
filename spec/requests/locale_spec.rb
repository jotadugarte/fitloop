# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Locale switcher", type: :request do
  self.use_transactional_tests = false

  describe "GET / [REQ-FIT-UI-005]" do
    it "defaults to English copy" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("DXF sheet nesting")
    end

    it "renders Spanish copy when the locale cookie is set" do
      cookies[:fitloop_locale] = "es"
      get root_path

      expect(response.body).to include("Anidado de láminas DXF")
    end

    it "renders the EN/ES toggle in the layout" do
      get root_path

      expect(response.body).to include("aria-label=\"#{I18n.t('locale.switcher_row_primary')}\"")
      expect(response.body).to include("EN")
      expect(response.body).to include("ES")
      expect(response.body).to include('data-controller="locale-switcher"')
      expect(response.body).to include('data-turbo="false"')
      expect(response.body).to include("locale-switcher#attachWorkspaceDraft")
    end

    it "localizes the EN/ES group aria-label in Spanish" do
      cookies[:fitloop_locale] = "es"
      get root_path

      label = I18n.t("locale.switcher_row_primary", locale: :es)
      expect(response.body).to include("aria-label=\"#{label}\"")
    end

    it "localizes the EN/ES group aria-label in es_panic" do
      cookies[:fitloop_locale] = "es_panic"
      get root_path

      label = I18n.t("locale.switcher_row_primary", locale: :es_panic)
      expect(response.body).to include("aria-label=\"#{label}\"")
    end

    it "renders panic copy when the locale cookie is set" do
      cookies[:fitloop_locale] = "es_panic"
      get root_path

      expect(response.body).to include("Tetris de supervivencia DXF")
    end

    it "renders the panic locale row with PÁNICO label, not ES_PANIC" do
      get root_path

      expect(response.body).to include("locale-switcher__btn--panic")
      expect(response.body).to include("📐 PÁNICO")
      expect(response.body).not_to include("ES_PANIC")
    end
  end

  describe "PATCH /locale [REQ-FIT-UI-005]" do
    it "persists Spanish in cookie and session then redirects back" do
      patch locale_path, params: { locale: "es" }, headers: { "HTTP_REFERER" => root_url }

      expect(response).to redirect_to(root_url)
      expect(cookies[:fitloop_locale]).to eq("es")
      follow_redirect!
      expect(response.body).to include("Anidado de láminas DXF")
    end

    it "persists es_panic in cookie and session then redirects back" do
      patch locale_path, params: { locale: "es_panic" }, headers: { "HTTP_REFERER" => root_url }

      expect(response).to redirect_to(root_url)
      expect(cookies[:fitloop_locale]).to eq("es_panic")
      follow_redirect!
      expect(response.body).to include("Tetris de supervivencia DXF")
    end

    it "ignores unsupported locales" do
      patch locale_path, params: { locale: "fr" }, headers: { "HTTP_REFERER" => root_url }

      expect(response).to redirect_to(root_url)
      expect(cookies[:fitloop_locale]).to be_nil
    end

    it "[REQ-FIT-UI-005] persists sheet inventory when switching locale from setup" do
      get start_project_path
      follow_redirect!
      project = Project.find(session[:workspace_project_id])
      expect(project.sheet_stocks).to be_empty

      patch locale_path,
            params: {
              locale: "en",
              project: {
                sheet_stocks_attributes: {
                  "0" => { width_mm: 1200, height_mm: 2400, quantity: 2, sort_order: 0, _destroy: "0" }
                }
              }
            },
            headers: { "HTTP_REFERER" => edit_project_path(project) }

      expect(response).to redirect_to(edit_project_path(project))
      project.reload
      expect(project.sheet_stocks.count).to eq(1)
      expect(project.sheet_stocks.first).to have_attributes(width_mm: 1200, height_mm: 2400, quantity: 2)
    end

    it "[REQ-FIT-UI-005] keeps sheet inventory on repeated locale switches" do
      get start_project_path
      follow_redirect!
      project = Project.find(session[:workspace_project_id])
      stock_attrs = { width_mm: 1200, height_mm: 2400, quantity: 2, sort_order: 0, _destroy: "0" }

      patch locale_path,
            params: { locale: "en", project: { sheet_stocks_attributes: { "0" => stock_attrs } } },
            headers: { "HTTP_REFERER" => edit_project_path(project) }
      follow_redirect!
      stock = project.reload.sheet_stocks.sole

      patch locale_path,
            params: {
              locale: "es",
              project: {
                sheet_stocks_attributes: {
                  "0" => stock_attrs.merge(id: stock.id)
                }
              }
            },
            headers: { "HTTP_REFERER" => edit_project_path(project) }
      follow_redirect!
      expect(project.reload.sheet_stocks).to contain_exactly(stock)

      patch locale_path,
            params: { locale: "es_panic", project: { sheet_stocks_attributes: { "0" => stock_attrs } } },
            headers: { "HTTP_REFERER" => edit_project_path(project) }
      expect(project.reload.sheet_stocks).to contain_exactly(stock)
    end

    it "[REQ-FIT-UI-005] [REQ-FIT-DXF-002] persists layer selection when switching locale from setup" do
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project = start_setup_session!

      post project_input_dxf_files_path(project),
           params: { "files[]" => [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      project.reload
      attachment = project.input_dxf_attachments.sole
      cut = project.project_layers.find_by!(layer_name: "PIECES", active_storage_attachment_id: attachment.id)
      layer_params = {
        attachment.id.to_s => {
          primary_layer_id: cut.id.to_s
        }
      }

      patch locale_path,
            params: { locale: "en", project_layers: layer_params },
            headers: { "HTTP_REFERER" => edit_project_path(project) }
      follow_redirect!
      expect(cut.reload).to have_attributes(layer_role: "primary", included: true)

      patch locale_path,
            params: { locale: "es" },
            headers: { "HTTP_REFERER" => edit_project_path(project) }
      expect(cut.reload).to have_attributes(layer_role: "primary", included: true)

      patch locale_path,
            params: { locale: "es_panic", project_layers: { attachment.id.to_s => {} } },
            headers: { "HTTP_REFERER" => edit_project_path(project) }
      expect(cut.reload).to have_attributes(layer_role: "primary", included: true)
    end
  end

  def start_setup_session!
    get start_project_path
    follow_redirect!
    Project.find(session[:workspace_project_id])
  end

  describe "collapsible panel persistence [REQ-FIT-UI-005]" do
    it "loads the Stimulus controller on project show for locale redirects" do
      get start_project_path
      follow_redirect!
      project = Project.find(session[:workspace_project_id])

      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="collapsible-persistence"')
      expect(response.body).to include('data-testid="show-sheet-inventory"')
      expect(response.body).to include('data-testid="source-dxf-detail"')
    end
  end
end
