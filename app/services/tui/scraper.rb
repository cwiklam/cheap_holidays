# frozen_string_literal: true

require 'nokogiri'
require 'net/http'
require 'uri'
require 'bigdecimal'

module Tui
  # Parses TUI HTML to extract offer data (hotel name, price, dates, URL, etc).
  # Does NOT fetch or persist data — focuses solely on parsing.
  class Scraper
    OFFER_CONTAINER_SELECTOR = 'div.offer-tile-wrapper.offer-tile-wrapper--listingOffer'
    HOTEL_NAME_SELECTOR      = 'header.offer-tile-body__header span'
    PRICE_SELECTOR           = 'span.price-value__amount, [data-testid="price-amount"]'
    DATE_RANGE_REGEX         = /\b\d{2}\.\d{2}\.\d{4}\s*[-–]\s*\d{2}\.\d{2}\.\d{4}\b/
    COUNTRY_DICTIONARY_PATH  = Rails.root.join('config', 'data', 'countries_pl.yml')

    # Whitelist of known country names, keyed by normalized (downcased,
    # squished) name, used to validate values scraped from breadcrumbs.
    # Guards against persisting non-country breadcrumb items (e.g. "Wakacje",
    # region/resort names) as bogus Country records.
    def self.known_countries
      @known_countries ||= begin
        names = YAML.load_file(COUNTRY_DICTIONARY_PATH) || []
        names.each_with_object({}) { |name, memo| memo[name.to_s.downcase.gsub(/\s+/, ' ').strip] = name }
      end
    rescue StandardError
      {}
    end

    def initialize(base_url:, use_browser: false)
      @base_url = base_url
      @use_browser = use_browser
    end

    def call(html:)
      return [] if html.blank?

      doc = Nokogiri::HTML(html)
      offers = parse_offers(doc)
      countries = extract_countries(doc)
      if countries.any?
        offers.each do |o|
          o[:countries] = countries
          o[:country] ||= countries.first
        end
      end
      offers
    end

    private

    def parse_offers(doc)
      doc.css(OFFER_CONTAINER_SELECTOR).map { |node| parse_offer(node) }.compact
    end

    def parse_offer(node)
      hotel_name = text_or_nil(node.at_css(HOTEL_NAME_SELECTOR))
      return nil if hotel_name.nil?

      href = node.at_css('a')&.[]('href')
      url = absolute_url(href)
      date_str = node.to_html.scan(DATE_RANGE_REGEX).first
      price_text = text_or_nil(node.at_css(PRICE_SELECTOR))
      price = to_decimal(price_text)

      {
        name:      hotel_name,
        url:       url,
        price:     price,
        price_raw: price_text,
        starts_on: date_str,
        raw_data:  collect_raw(node)
      }
    end

    def extract_countries(doc)
      return [] unless doc

      nodes = doc.css('ol.breadcrumbs__list a.breadcrumbs__anchor span:not([class])')
      names = nodes.map { |n| squish(n.text) }.reject(&:empty?)
      names.uniq.filter_map { |name| known_country_name(name) }
    rescue StandardError
      []
    end

    # Resolves a scraped breadcrumb value against the country dictionary,
    # returning the canonical dictionary name, or nil if it isn't a real
    # country (e.g. "Wakacje", a region, or a hotel/menu label).
    def known_country_name(name)
      self.class.known_countries[name.to_s.downcase.gsub(/\s+/, ' ').strip]
    end

    def collect_raw(node)
      data_attrs = {}
      node.traverse do |el|
        next unless el.element?

        el.attribute_nodes.each do |attr|
          next unless attr.name.start_with?('data-')

          (data_attrs[attr.name] ||= []) << attr.value
        end
      end
      data_attrs.transform_values!(&:uniq)

      {
        container_classes:   node['class'],
        raw_text:            squish(node.text),
        raw_html:            node.to_html,
        detected_date:       node.to_html.scan(DATE_RANGE_REGEX).first,
        detected_price_text: text_or_nil(node.at_css(PRICE_SELECTOR))
      }.merge(data_attrs)
    end

    def text_or_nil(el)
      return nil unless el

      squish(el.text)
    end

    def squish(str)
      str.to_s.gsub(/\s+/, ' ').strip
    end

    def to_decimal(str)
      return nil if str.to_s.strip.empty?

      s = str.gsub(/[^\d,\.\-]/, '')
      if s.count(',') == 1 && s.count('.') == 0
        s = s.tr(',', '.')
      else
        s = s.gsub(/[[:space:]\u00A0\u202F.]/, '')
      end
      BigDecimal(s)
    rescue ArgumentError
      nil
    end

    def absolute_url(href)
      return nil if href.to_s.empty?

      URI.join(@base_url, href).to_s
    rescue StandardError
      href
    end
  end
end
