# frozen_string_literal: true

module TravelAgencies
  # Thin job entry point. All fetching/parsing/persistence is delegated to Itaka::Fetcher.
  class ItakaSequentialFetchJob < ApplicationJob
    queue_as :default

    def perform(page: 1, query: nil, max_pages: 100)
      agency = ::TravelAgency.find_by(name_id: 'itaka')
      return unless agency

      page = page.to_i
      return if page <= 0

      fetcher = ::Itaka::Fetcher.new(agency: agency, page: page, query: query, max_pages: max_pages)
      fetcher.call
    end
  end
end

