# frozen_string_literal: true

module Tui
  # Orchestrates TUI data fetching: HTML retrieval, parsing, and persistence.
  # Delegates to BrowserFetcher or HttpFetcher based on availability.
  class Fetcher
    def initialize(agency:, page: 1, query: nil, max_pages: 100)
      @agency = agency
      @page = page.to_i
      @query = query.to_s
      @max_pages = max_pages
      @unlimited = max_pages.nil?
    end

    def call
      return false if @page <= 0
      return false unless @unlimited || @page <= @max_pages.to_i

      html_batches = if ferrum_available?
                       fetch_with_browser
                     else
                       fetch_with_http
                     end

      return false if html_batches.blank?

      all_offers = []
      html_batches.each do |html|
        offers = ::Tui::Scraper.new(base_url: @agency.url).call(html: html)
        offers.select! { |o| o[:name].to_s.downcase.include?(@query.downcase) } if @query.present?
        all_offers.concat(offers)
      end

      if all_offers.blank?
        Rails.logger.info("TuiSequentialFetchJob: no offers on page=#{@page} agency=#{@agency.id}, stopping")
        return false
      end

      persist_countries_hotels_offers(@agency, all_offers)
      enqueue_next_page_if_needed
      true
    end

    private

    def ferrum_available?
      require 'ferrum'
      true
    rescue LoadError
      false
    end

    def fetch_with_browser
      fetcher = ::Tui::BrowserFetcher.new(base_url: @agency.url, timeout: 25)
      fetcher.call
    rescue StandardError => e
      Rails.logger.info("TuiSequentialFetchJob: browser fetch error: #{e.message}")
      []
    end

    def fetch_with_http
      html = ::Tui::HttpFetcher.new(agency: @agency, page: @page).call
      return [] if html.blank?

      [html]
    rescue StandardError => e
      Rails.logger.info("TuiSequentialFetchJob: HTTP fetch error on page=#{@page}: #{e.message}")
      []
    end

    def enqueue_next_page_if_needed
      return if ferrum_available? # Browser mode handles all pages in one call

      next_page = @page + 1
      return if !@unlimited && next_page > @max_pages.to_i

      if @agency.next_page_url.blank?
        Rails.logger.info("TuiSequentialFetchJob: next_page_url blank, stopping after page=#{@page} agency=#{@agency.id}")
        return
      end

      ::TravelAgencies::TuiSequentialFetchJob.perform_later(page: next_page, query: @query.presence, max_pages: @max_pages)
    end

    def persist_countries_hotels_offers(agency, offers)
      countries_map = {}
      offers.each do |offer|
        countries_list = Array(offer[:countries]).map { |c| c.to_s.strip }.reject(&:empty?)
        countries_list = [offer[:country].to_s.strip].reject(&:empty?) if countries_list.empty? && offer[:country].present?
        countries_list.uniq!

        resolved_countries = []
        countries_list.each do |cname|
          normalized = ::Country.normalize(cname)
          country_rec = countries_map[normalized] ||= ::Country.where(normalized_name: normalized).first_or_create(name: cname)
          resolved_countries << country_rec
        end
        main_country = resolved_countries.first

        hotel = find_or_initialize_hotel(offer)
        save_hotel(hotel, offer, main_country, agency)
        begin
          rd = (hotel.raw_data || {}).dup
          rd[:countries] = countries_list if countries_list.any?
          hotel.update_column(:raw_data, rd)
        rescue StandardError
        end

        persist_offer_snapshot(hotel, offer, agency)
      end
    end

    def find_or_initialize_hotel(offer)
      if offer[:url].present?
        ::Hotel.where(url: offer[:url]).first_or_initialize
      else
        ::Hotel.where(name: offer[:name]).first_or_initialize
      end
    end

    def save_hotel(hotel, offer, country, agency)
      hotel.name = offer[:name]
      hotel.url = offer[:url] if offer[:url].present?
      hotel.country = country if country
      hotel.image_url = offer[:image_url] if offer[:image_url].present?
      hotel.source_fetched_at = Time.current
      hotel.raw_data = offer
      hotel.travel_agency ||= agency if hotel.respond_to?(:travel_agency) && hotel.travel_agency.nil?
      hotel.save(validate: true)
    rescue ActiveRecord::RecordInvalid
      nil
    end

    def persist_offer_snapshot(hotel, offer, agency)
      return unless defined?(::Offer)
      return if hotel.nil? || !hotel.persisted?

      existing = hotel.offers.where(url: offer[:url], starts_on: offer[:starts_on], travel_agency_id: agency.id, price: offer[:price]).order(created_at: :desc).first
      return if existing

      record = hotel.offers.build
      record.name = offer[:name]
      record.url = offer[:url]
      record.price = offer[:price]
      record.price_raw = offer[:price_raw]
      record.starts_on = offer[:starts_on]
      record.source_fetched_at = Time.current
      record.raw_data = offer
      record.travel_agency = agency
      record.save(validate: true)
    rescue ActiveRecord::RecordInvalid
      nil
    end
  end
end
