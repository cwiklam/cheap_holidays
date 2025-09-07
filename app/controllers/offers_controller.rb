# frozen_string_literal: true
class OffersController < ApplicationController
  before_action :set_travel_agencies, only: %i[current]

  def index
    @q = params[:q].to_s.strip
    @country = params[:country].to_s.strip.presence
    @agency_id = params[:agency_id].to_s.strip.presence
    @start_contains = params[:start].to_s.strip.presence

    scope = Offer.includes(:hotel, :country, :travel_agency).order(created_at: :desc)
    scope = scope.where("offers.name ILIKE ?", "%#{@q}%") if @q.present?
    scope = scope.where("offers.starts_on ILIKE ?", "%#{@start_contains}%") if @start_contains.present?
    scope = scope.joins(:country).where("countries.normalized_name = ?", Country.normalize(@country)) if @country.present?
    scope = scope.where(travel_agency_id: @agency_id) if @agency_id.present?

    @offers = scope.limit(200) # prosty limit bezpieczeństwa
  end

  # GET /travel_agencies/:id/offers
  def current
    @query = params[:q].to_s.strip
    fetch_source_html
    @offers = []
    @scrape_info = {}

    if @fetched_html && @fetch_error.nil?
      scraper = ItakaScraper.new(@fetched_html, base_url: @travel_agency.url)
      @offers = scraper.offers
      @scrape_info = scraper.diagnostics
      @offers.select! { |o| o[:name].to_s.downcase.include?(@query.downcase) } if @query.present?
      persist_countries_and_hotels(@offers)
    end

    render 'offers/current'
  end

  private

  def set_travel_agencies
    @travel_agencies = TravelAgency.includes().all
  end

  def fetch_source_html
    @fetched_html = nil
    @fetch_error = nil
    begin
      conn = Faraday.new do |f|
        f.options.timeout = 10
        f.options.open_timeout = 7
        f.adapter Faraday.default_adapter
      end
      response = conn.get(@travel_agency.url)
      if response.success?
        raw = response.body.to_s
        max_len = 300_000
        @fetched_html = raw.bytesize > max_len ? raw.byteslice(0, max_len) + "\n<!-- truncated -->" : raw
      else
        @fetch_error = "Fetch failed status: #{response.status}"
      end
    rescue => e
      @fetch_error = "Fetch error: #{e.class}: #{e.message}"
    end
  end

  def persist_countries_and_hotels(offers)
    countries_found = offers.map { |o| o[:country] }.compact.map(&:strip).reject(&:empty?)
    return if countries_found.empty?

    countries_map = {}
    countries_found.uniq.each do |country_name|
      normalized = Country.normalize(country_name)
      countries_map[country_name] = Country.where(normalized_name: normalized).first_or_create(name: country_name)
    rescue ActiveRecord::RecordInvalid
      next
    end

    offers.each do |offer|
      country = offer[:country].present? ? countries_map[offer[:country]] : nil
      hotel = find_or_initialize_hotel(offer, country)
      save_hotel(hotel, offer, country)
      persist_offer_snapshot(hotel, offer)
    end
  end

  def find_or_initialize_hotel(offer, country)
    scope = Hotel
    if offer[:url].present?
      scope.where(url: offer[:url]).first_or_initialize
    else
      scope.where(name: offer[:name]).first_or_initialize
    end
  end

  def save_hotel(hotel, offer, country)
    hotel.name = offer[:name]
    hotel.url = offer[:url] if offer[:url].present?
    hotel.country = country if country
    hotel.image_url = offer[:image_url] if offer[:image_url].present?
    hotel.source_fetched_at = Time.current
    hotel.raw_data = offer
    hotel.travel_agency ||= @travel_agency if hotel.respond_to?(:travel_agency) && hotel.travel_agency.nil?
    hotel.save(validate: true)
  rescue ActiveRecord::RecordInvalid
    # Ignore invalid hotel record for now; could log
  end

  def persist_offer_snapshot(hotel, offer)
    return unless defined?(Offer)
    return if hotel.nil? || !hotel.persisted?

    key_scope = hotel.offers
    key_scope = key_scope.where(url: offer[:url]) if offer[:url].present?
    key_scope = key_scope.where(starts_on: offer[:starts_on]) if offer[:starts_on].present?

    record = key_scope.first_or_initialize
    record.name = offer[:name]
    record.url = offer[:url]
    record.price = offer[:price]
    record.price_raw = offer[:price_raw]
    record.starts_on = offer[:starts_on]
    record.source_fetched_at = Time.current
    record.raw_data = offer
    record.travel_agency ||= hotel.travel_agency || @travel_agency
    record.save(validate: true)
  rescue ActiveRecord::RecordInvalid
    # Ignore invalid offer snapshot; could log
  end
end
