# frozen_string_literal: true

module TravelAgencies
  # Fetches Itaka offers page by page by enqueueing itself for the next page.
  # Stops when: page > max_pages, no offers parsed, or travel agency missing.
  class ItakaSequentialFetchJob < ApplicationJob
    queue_as :default

    # @param travel_agency_id [Integer]
    # @param page [Integer]
    # @param query [String, nil]
    # @param max_pages [Integer]
    def perform(travel_agency_id, page: 1, query: nil, max_pages: 10)
      agency = ::TravelAgency.find_by(id: travel_agency_id)
      return unless agency
      return if page.to_i <= 0
      return if page.to_i > max_pages.to_i

      url = build_page_url(agency, page.to_i)
      return if url.blank?

      html, error = fetch_html(url)
      return if error || html.blank?

      scraper = ::ItakaScraper.new(html, base_url: agency.url)
      offers = scraper.offers
      offers.select! { |o| o[:name].to_s.downcase.include?(query.to_s.downcase) } if query.present?

      if offers.blank?
        Rails.logger.info("ItakaSequentialFetchJob: no offers on page=#{page} agency=#{agency.id}, stopping")
        return
      end

      persist_countries_hotels_offers(agency, offers)

      next_page = page.to_i + 1
      return if next_page > max_pages.to_i

      # Enqueue next page
      self.class.perform_later(agency.id, page: next_page, query: query, max_pages: max_pages)
    end

    private

    def build_page_url(agency, page)
      return agency.url if page == 1
      return nil if agency.next_page_url.blank?

      base = agency.next_page_url.to_s
      # Ensure relative/absolute merge
      begin
        absolute_base = base =~ %r{^https?://}i ? base : URI.join(agency.url, base).to_s
      rescue
        absolute_base = agency.url.to_s + base.to_s
      end
      # Avoid duplicate page numbers if already present
      if absolute_base.match?(/\d+$/)
        absolute_base.sub(/\d+$/, page.to_s)
      else
        absolute_base + page.to_s
      end
    end

    def fetch_html(url)
      conn = Faraday.new do |f|
        f.options.timeout      = 12
        f.options.open_timeout = 7
        f.adapter Faraday.default_adapter
      end
      response = conn.get(url)
      if response.success?
        raw     = response.body.to_s
        max_len = 400_000
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

      # uniqueness: per hotel, date(range) & url. Accept new snapshot if price differs.
      existing = hotel.offers.where(url: offer[:url], starts_on: offer[:starts_on]).order(created_at: :desc).first
      if existing && existing.price.to_f == offer[:price].to_f
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

