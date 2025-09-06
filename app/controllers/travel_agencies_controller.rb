# frozen_string_literal: true
class TravelAgenciesController < ApplicationController
  before_action :set_travel_agency, only: %i[ show edit update destroy offers ]

  def index
    @travel_agencies = TravelAgency.order(:name)
  end

  def show; end

  def new
    @travel_agency = TravelAgency.new
  end

  def edit; end

  def create
    @travel_agency = TravelAgency.new(travel_agency_params)
    if @travel_agency.save
      redirect_to @travel_agency, notice: "Travel agency was successfully created."
    else
      flash.now[:alert] = "Could not create agency."
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @travel_agency.update(travel_agency_params)
      redirect_to @travel_agency, notice: "Travel agency was successfully updated."
    else
      flash.now[:alert] = "Could not update agency."
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @travel_agency.destroy
    redirect_to travel_agencies_path, notice: "Travel agency was successfully deleted."
  end

  def offers
    @query = params[:q].to_s.strip
    @fetched_html = nil
    @fetch_error = nil
    begin
      conn = Faraday.new do |f|
        f.options.timeout = 5
        f.options.open_timeout = 3
        f.adapter Faraday.default_adapter
      end
      response = conn.get(@travel_agency.url)
      if response.success?
        raw = response.body.to_s
        max_len = 100_000
        @fetched_html = raw.bytesize > max_len ? raw.byteslice(0, max_len) + "\n<!-- truncated -->" : raw
      else
        @fetch_error = "Fetch failed status: #{response.status}"
      end
    rescue => e
      @fetch_error = "Fetch error: #{e.class}: #{e.message}"
    end

    @offers = []
    @scrape_info = {}
    if @fetched_html && @fetch_error.nil?
      scraper = OfferScraper.new(@fetched_html, base_url: @travel_agency.url)
      @offers = scraper.offers
      @scrape_info = scraper.diagnostics
      @offers.select! { |o| o[:name].to_s.downcase.include?(@query.downcase) } if @query.present?

      # Persistuj kraje znalezione w ofertach
      countries_found = @offers.map { |o| o[:country] }.compact.map(&:strip).reject(&:empty?)
      if countries_found.any?
        countries_found.uniq.each do |country_name|
          normalized = Country.normalize(country_name)
          country = Country.where(normalized_name: normalized).first_or_create(name: country_name)
          # @@@@@ tworzenie / aktualizacja hoteli dla tego kraju
          related_offers = @offers.select { |o| o[:country].to_s.strip.casecmp(country_name.strip).zero? }
          related_offers.each do |offer|
            # Identyfikacja hotelu: preferuj kombinację (url) jeśli dostępna, inaczej (name)
              finder_scope = @travel_agency.hotels
              hotel = if offer[:url].present?
                        finder_scope.where(url: offer[:url]).first_or_initialize
                      else
                        finder_scope.where(name: offer[:name]).first_or_initialize
                      end
              hotel.name = offer[:name]
              hotel.url = offer[:url] if offer[:url].present?
              hotel.country = country
              hotel.image_url = offer[:image_url] if offer[:image_url].present?
              hotel.source_fetched_at = Time.current
              # Przechowujemy pełne dane źródłowe (łącznie z ceną i zakresem dat) w raw_data.
              hotel.raw_data = offer
              # Zapis bez walidacji dodatkowych (model wymaga tylko name); można zmienić na validate: true gdy dodamy walidacje.
              hotel.save(validate: true)
          end
        rescue ActiveRecord::RecordInvalid
          # Ignoruj pojedyncze błędy walidacji kraju / hotelu – opcjonalnie log
        end
      end
    end
  end

  private

  def set_travel_agency
    @travel_agency = TravelAgency.find(params[:id])
  end

  def travel_agency_params
    params.require(:travel_agency).permit(:name, :description, :url)
  end
end
