# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workspace, "[REQ-FIT-AUTH-001] [REQ-FIT-DOM-001]" do
  before { Project.destroy_all }

  describe ".purge_all_ephemeral! [REQ-FIT-DOM-001]" do
    it "[REQ-FIT-DOM-001] removes all ephemeral projects and sheet stocks" do
      ephemeral = Project.create!(ephemeral: true, title: "Ephemeral", status: :draft)
      ephemeral.sheet_stocks.create!(width_mm: 1000, height_mm: 1000, quantity: 1, sort_order: 0)
      Project.create!(
        ephemeral: false,
        title: "Saved",
        sheet_stocks_attributes: { "0" => { width_mm: 500, height_mm: 500, quantity: 1, sort_order: 0 } }
      )

      count = described_class.purge_all_ephemeral!

      expect(count).to eq(1)
      expect(Project.ephemeral.count).to eq(0)
      expect(SheetStock.count).to eq(1)
    end
  end

  describe ".purge_all! [REQ-FIT-DOM-001]" do
    it "[REQ-FIT-DOM-001] removes every project and sheet stock" do
      Project.create!(ephemeral: true, title: "A", status: :draft)
      Project.create!(
        ephemeral: false,
        title: "B",
        sheet_stocks_attributes: { "0" => { width_mm: 500, height_mm: 500, quantity: 1, sort_order: 0 } }
      )

      counts = described_class.purge_all!

      expect(counts[:projects]).to eq(2)
      expect(Project.count).to eq(0)
      expect(SheetStock.count).to eq(0)
    end
  end

  describe ".resolve! [REQ-FIT-AUTH-001]" do
    it "[REQ-FIT-AUTH-001] returns the ephemeral project when the session is bound" do
      project = Project.create!(ephemeral: true, title: "Mine", status: :draft)
      session = { described_class::SESSION_KEY => project.id }

      expect(described_class.resolve!(session, project.id)).to eq(project)
    end

    it "[REQ-FIT-AUTH-001] raises when the ephemeral project id is not bound to the session" do
      project = Project.create!(ephemeral: true, title: "Other", status: :draft)

      expect do
        described_class.resolve!({}, project.id)
      end.to raise_error(ActiveRecord::RecordNotFound, /not bound/)
    end

    it "[REQ-FIT-AUTH-001] raises when the session is bound to a different project" do
      mine = Project.create!(ephemeral: true, title: "Mine", status: :draft)
      other = Project.create!(ephemeral: true, title: "Other", status: :draft)
      session = { described_class::SESSION_KEY => mine.id }

      expect do
        described_class.resolve!(session, other.id)
      end.to raise_error(ActiveRecord::RecordNotFound, /not bound/)
    end

    it "[REQ-FIT-AUTH-001] raises when the project id does not exist" do
      session = { described_class::SESSION_KEY => 999_999 }

      expect do
        described_class.resolve!(session, 999_999)
      end.to raise_error(ActiveRecord::RecordNotFound, /discarded/)
    end

    it "[REQ-FIT-AUTH-001] raises when the bound project was discarded" do
      project = Project.create!(ephemeral: true, title: "Gone", status: :draft)
      session = { described_class::SESSION_KEY => project.id }
      project.destroy!

      expect do
        described_class.resolve!(session, project.id)
      end.to raise_error(ActiveRecord::RecordNotFound, /discarded/)

      expect(session[described_class::SESSION_KEY]).to be_nil
    end

    it "[REQ-FIT-AUTH-001] finds a bound project on any tab when prefer_tab_id misses" do
      tab_a = "tab-a"
      tab_b = "tab-b"
      project = Project.create!(ephemeral: true, title: "Workshop", status: :draft)
      session = { described_class::WORKSPACES_KEY => { tab_a => project.id } }

      expect(described_class.any_bound_project(session, prefer_tab_id: tab_b)).to eq(project)
    end

    it "[REQ-FIT-AUTH-001] clears a stale bind when the ephemeral project was discarded" do
      project = Project.create!(ephemeral: true, title: "Gone", status: :draft)
      session = { described_class::WORKSPACES_KEY => { described_class::DEFAULT_TAB_ID => project.id } }
      project.destroy!

      expect(described_class.find(session)).to be_nil
      expect(session[described_class::WORKSPACES_KEY]).to be_empty
    end

    it "[REQ-FIT-AUTH-001] does not resolve non-ephemeral projects by id" do
      saved = Project.create!(
        ephemeral: false,
        title: "Saved",
        sheet_stocks_attributes: { "0" => { width_mm: 500, height_mm: 500, quantity: 1, sort_order: 0 } }
      )
      session = { described_class::SESSION_KEY => saved.id }

      expect do
        described_class.resolve!(session, saved.id)
      end.to raise_error(ActiveRecord::RecordNotFound, /discarded/)
    end
  end

  describe "tab-scoped session[:workspaces] [REQ-FIT-AUTH-001]" do
    let(:tab_a) { "11111111-1111-4111-8111-111111111111" }
    let(:tab_b) { "22222222-2222-4222-8222-222222222222" }
    let(:session) { {} }

    it "[REQ-FIT-AUTH-001] binds independent projects per tab_id (D21)" do
      project_a = Project.create!(ephemeral: true, title: "Tab A", status: :draft)
      project_b = Project.create!(ephemeral: true, title: "Tab B", status: :draft)

      described_class.bind!(session, project_a, tab_id: tab_a)
      described_class.bind!(session, project_b, tab_id: tab_b)

      expect(session[described_class::WORKSPACES_KEY]).to eq(
        tab_a => project_a.id,
        tab_b => project_b.id
      )
      expect(described_class.resolve!(session, project_a.id, tab_id: tab_a)).to eq(project_a)
      expect(described_class.resolve!(session, project_b.id, tab_id: tab_b)).to eq(project_b)
    end

    it "[REQ-FIT-AUTH-001] raises when resolving a project from the wrong tab_id" do
      project = Project.create!(ephemeral: true, title: "Mine", status: :draft)
      described_class.bind!(session, project, tab_id: tab_a)

      expect do
        described_class.resolve!(session, project.id, tab_id: tab_b)
      end.to raise_error(ActiveRecord::RecordNotFound, /not bound/)
    end

    it "[REQ-FIT-AUTH-001] discards only the tab being closed (D21)" do
      project_a = Project.create!(ephemeral: true, title: "Tab A", status: :draft)
      project_b = Project.create!(ephemeral: true, title: "Tab B", status: :draft)
      described_class.bind!(session, project_a, tab_id: tab_a)
      described_class.bind!(session, project_b, tab_id: tab_b)

      described_class.discard!(session, tab_id: tab_a)

      expect(session[described_class::WORKSPACES_KEY]).to eq(tab_b => project_b.id)
      expect(Project.exists?(project_a.id)).to be(false)
      expect(Project.exists?(project_b.id)).to be(true)
    end

    it "[REQ-FIT-AUTH-001] finds the bound project for a tab_id" do
      project = Project.create!(ephemeral: true, title: "Tab", status: :draft)
      described_class.bind!(session, project, tab_id: tab_a)

      expect(described_class.find(session, tab_id: tab_a)).to eq(project)
      expect(described_class.find(session, tab_id: tab_b)).to be_nil
    end

    it "[REQ-FIT-AUTH-001] detects bind via bound_to_project? regardless of tab_id (D42)" do
      project = Project.create!(ephemeral: true, title: "Tab", status: :draft)
      described_class.bind!(session, project, tab_id: tab_a)

      expect(described_class.bound_to_project?(session, project)).to be(true)
      expect(described_class.bound_to_project?(session, project.id)).to be(true)
      expect(described_class.find(session, tab_id: tab_b)).to be_nil
    end
  end

  describe "tab-close TTL [REQ-FIT-AUTH-001]" do
    let(:tab_id) { "33333333-3333-4333-8333-333333333333" }
    let(:session) { {} }

    it "[REQ-FIT-AUTH-001] does not expire projects based on last_activity_at idle time (D20)" do
      project = Project.create!(
        ephemeral: true,
        title: "Idle",
        status: :draft,
        last_activity_at: 10.minutes.ago
      )
      described_class.bind!(session, project, tab_id: tab_id)

      expect(described_class.resolve!(session, project.id, tab_id: tab_id)).to eq(project)
      expect(Project.exists?(project.id)).to be(true)
    end

    it "[REQ-FIT-AUTH-001] expires tab bind via expire_tab_after_closure! (D20)" do
      project = Project.create!(ephemeral: true, title: "Leave", status: :draft)
      described_class.bind!(session, project, tab_id: tab_id)

      described_class.expire_tab_after_closure!(session, tab_id: tab_id)

      expect(Project.exists?(project.id)).to be(false)
      expect(session.dig(described_class::WORKSPACES_KEY, tab_id)).to be_nil
    end
  end
end
