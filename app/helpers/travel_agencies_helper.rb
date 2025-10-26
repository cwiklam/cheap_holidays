# app/helpers/travel_agencies_helper.rb
module TravelAgenciesHelper
  def travel_agency_edit_link(agency, label: 'Edit', **options)
    link_to label, edit_travel_agency_path(agency), **options
  end
end