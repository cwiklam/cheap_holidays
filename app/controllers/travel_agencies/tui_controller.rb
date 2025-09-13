module TravelAgencies
  class TuiController < ApplicationController
    before_action :set_travel_agency

    def fetch
    end

    private

    def set_travel_agency
      @travel_agency = TravelAgency.find_by(name_id: 'tui')
    end
  end
end