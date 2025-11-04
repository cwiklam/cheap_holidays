# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

TravelAgency.transaction do
  itaka_url = "https://www.itaka.pl/last-minute/"
  tui_url = "https://www.tui.pl/last-minute?pm_source=MENU&pm_name=Last_Minute&q=%3AflightDate%3AbyPlane%3AT%3AadditionalType%3AGT03%2523TUZ-LAST25%3AdF%3A6%3AdT%3A14%3ActAdult%3A2%3ActChild%3A0%3AminHotelCategory%3AdefaultHotelCategory%3AtripAdvisorRating%3AdefaultTripAdvisorRating%3Abeach_distance%3AdefaultBeachDistance%3AtripType%3AWS&fullPrice=false"
  FactoryBot.create(:travel_agency, name: "ITAKA", name_id: 'itaka', url: itaka_url, next_page_url: '?page=') unless TravelAgency.exists?(name_id: 'itaka')
  FactoryBot.create(:travel_agency, name: "TUI", name_id: 'tui', url: tui_url, next_page_url: '?page=') unless TravelAgency.exists?(name_id: 'tui')
end