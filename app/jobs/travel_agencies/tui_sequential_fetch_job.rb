# frozen_string_literal: true

module TravelAgencies
  # Sequentially fetches TUI offers page-by-page. Stops when:
  # 1) no offers parsed; 2) fetch error; 3) travel agency missing; 4) optional max_pages exceeded.
  # This emulates clicking the "Show more" button by requesting the next page URL pattern.
  class TuiSequentialFetchJob < ApplicationJob
    queue_as :default

    # @param travel_agency_id [Integer]
    # @param page [Integer]
    # @param query [String, nil]
    # @param max_pages [Integer, nil] if nil => unlimited until no offers or error
    def perform(travel_agency_id, page: 1, query: nil, max_pages: nil)
      agency = ::TravelAgency.find_by(id: travel_agency_id)
      return unless agency
      return if page.to_i <= 0

      unlimited = max_pages.nil?
      unless unlimited
        return if page.to_i > max_pages.to_i
      end

      url = build_page_url(agency, page.to_i)
      return if url.blank?

      # Prefer headless browser via TuiScraper to allow JS-rendered content and to wait for final page
      offers = []
      begin
        scraper = ::TuiScraper.new(base_url: url, http_timeout: 20, use_browser: true)
        offers  = scraper.call
      rescue => e
        Rails.logger.info("TuiSequentialFetchJob: scraper error on page=#{page} agency=#{agency.id} error=#{e.message}")
        # Fallback: try raw HTTP if browser path failed
        html, error = fetch_html(url)
        if error || html.blank?
          Rails.logger.info("TuiSequentialFetchJob: fetch error on page=#{page} agency=#{agency.id} error=#{error}")
          return
        end
        # Use agency.url as base for absolutizing if fallback path
        offers = ::TuiScraper.new(base_url: agency.url, use_browser: false).call(html: html)
      end

      offers.select! { |o| o[:name].to_s.downcase.include?(query.to_s.downcase) } if query.present?

      if offers.blank?
        Rails.logger.info("TuiSequentialFetchJob: no offers on page=#{page} agency=#{agency.id}, stopping")
        return
      end

      persist_countries_hotels_offers(agency, offers)

      next_page = page.to_i + 1
      unless unlimited
        return if next_page > max_pages.to_i
      end

      if agency.next_page_url.blank?
        Rails.logger.info("TuiSequentialFetchJob: next_page_url blank, stopping after page=#{page} agency=#{agency.id}")
        return
      end

      self.class.perform_later(agency.id, page: next_page, query: query, max_pages: max_pages)
    end

    private

    def build_page_url(agency, page)
      return agency.url if page == 1
      return nil if agency.next_page_url.blank?

      base = agency.next_page_url.to_s
      # Merge relative path with base url
      absolute_base = begin
        base =~ %r{^https?://}i ? base : URI.join(agency.url, base).to_s
      rescue
        agency.url.to_s + base.to_s
      end

      # If base already ends with a number, replace it with the page; else append page
      if absolute_base.match?(/\d+$/)
        absolute_base.sub(/\d+$/, page.to_s)
      else
        absolute_base + page.to_s
      end
    end

    def fetch_html(url)
      conn = Faraday.new do |f|
        f.options.timeout      = 15
        f.options.open_timeout = 8
        f.adapter Faraday.default_adapter
      end
      response = conn.get(url)
      if response.success?
        raw     = response.body.to_s
        max_len = 500_000
        html    = raw.bytesize > max_len ? raw.byteslice(0, max_len) + "\n<!-- truncated -->" : raw
        [html, nil]
      else
        [nil, "status=#{response.status}"]
      end
    rescue => e
      [nil, e.message]
    end

    def persist_countries_hotels_offers(agency, offers)
      countries_map = {}
      offers.each do |offer|
        country = nil
        if offer[:country].present?
          country_name = offer[:country].strip
          unless country_name.empty?
            normalized = ::Country.normalize(country_name)
            country = countries_map[normalized] ||= ::Country.where(normalized_name: normalized).first_or_create(name: country_name)
          end
        end

        hotel = find_or_initialize_hotel(offer)
        save_hotel(hotel, offer, country, agency)
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
      # ignore invalid hotel
    end

    def persist_offer_snapshot(hotel, offer, agency)
      return unless defined?(::Offer)
      return if hotel.nil? || !hotel.persisted?

      existing = hotel.offers.where(url: offer[:url], starts_on: offer[:starts_on], travel_agency_id: agency.id, price: offer[:price]).order(created_at: :desc).first
      if existing
        return
      end

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
      # ignore offer errors
    end
  end
end

