# frozen_string_literal: true

module TravelAgencies
  # Uruchamia dla każdej agencji ItakaSequentialFetchJob (start od strony 1, bez limitu stron).
  # Wywoływany cyklicznie przez harmonogram (recurring.yml) dwa razy dziennie.
  class ItakaDailySchedulerJob < ApplicationJob
    queue_as :default

    def perform
      itaka_agency = ::TravelAgency.find_by(name: 'ITAKA')
      return if agencies.empty?

      agencies.find_each do |agency|
        TravelAgencies::ItakaSequentialFetchJob.perform_later(agency.id, page: 1, max_pages: nil)
      end
    end
  end
end

