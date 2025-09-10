# frozen_string_literal: true
class OffersController < ApplicationController
  def index
    @q = params[:q].to_s.strip
    @country = params[:country].to_s.strip.presence
    @agency_id = params[:agency_id].to_s.strip.presence
    @start_contains = params[:start].to_s.strip.presence

    scope = Offer.includes(:hotel, :travel_agency).order(created_at: :desc)
    scope = scope.where("offers.name ILIKE ?", "%#{@q}%") if @q.present?
    scope = scope.where("offers.starts_on ILIKE ?", "%#{@start_contains}%") if @start_contains.present?
    scope = scope.joins(:country).where("countries.normalized_name = ?", Country.normalize(@country)) if @country.present?
    scope = scope.where(travel_agency_id: @agency_id) if @agency_id.present?

    @offers = scope.limit(200) # simple safety limit
  end
end
