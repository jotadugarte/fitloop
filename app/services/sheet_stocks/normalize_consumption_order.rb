# frozen_string_literal: true

module SheetStocks
  # [REQ-FIT-DOM-001] Dense consumption ranks: all finite stocks first (stable by prior
  # sort_order), then unlimited (quantity nil) stocks last.
  class NormalizeConsumptionOrder
    def self.call(project)
      new(project).call
    end

    def initialize(project)
      @project = project
    end

    def call
      stocks = active_stocks
      return if stocks.empty?

      ordered = finites_in_prior_order(stocks) + unlimited_in_prior_order(stocks)
      assign_dense_ranks(ordered)
    end

    private

    def active_stocks
      @project.sheet_stocks.reject(&:marked_for_destruction?)
    end

    def finites_in_prior_order(stocks)
      stocks
        .reject { |stock| stock.quantity.nil? }
        .sort_by(&:sort_order)
    end

    def unlimited_in_prior_order(stocks)
      stocks
        .select { |stock| stock.quantity.nil? }
        .sort_by(&:sort_order)
    end

    def assign_dense_ranks(ordered_stocks)
      ordered_stocks.each_with_index do |stock, rank|
        stock.sort_order = rank
      end
    end

    # Persist in-memory rank changes (e.g. before nesting when project.save is not called).
    def self.persist!(project)
      project.sheet_stocks.select(&:changed?).each(&:save!)
    end
  end
end
