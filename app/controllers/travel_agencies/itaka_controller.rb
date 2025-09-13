module TravelAgencies
  class ItakaController < ApplicationController
    before_action :set_travel_agency

    def fetch
      query = params[:q].to_s.strip.presence
      max_pages = params[:max_pages].to_i
      max_pages = 10 if max_pages <= 0
      max_pages = 50 if max_pages > 50

      TravelAgencies::ItakaSequentialFetchJob.perform_later(@travel_agency.id, page: 1, query: query, max_pages: max_pages)
      redirect_to travel_agency_path(@travel_agency), notice: 'Fetch job enqueued. Offers will be processed in background.'
    end

    private

    def set_travel_agency
      identifier = params[:travel_agency_id] || params[:id]
      @travel_agency = TravelAgency.find(identifier)
    end
  end
end