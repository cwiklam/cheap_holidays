# frozen_string_literal: true

require 'nokogiri'
require 'net/http'
require 'uri'
require 'bigdecimal'

module TravelAgencies
  class TuiScraper
    OFFER_CONTAINER_SELECTOR = 'div.offer-tile-wrapper.offer-tile-wrapper--listingOffer'
    HOTEL_NAME_SELECTOR      = 'span.offer-tile-body__hotel-name'
    PRICE_SELECTOR           = 'span.price-value__amount, [data-testid="price-amount"]'
    DATE_RANGE_REGEX         = /\b\d{2}\.\d{2}\.\d{4}\s*[-–]\s*\d{2}\.\d{2}\.\d{4}\b/

    def initialize(base_url:, http_timeout: 15, user_agent: default_user_agent)
      @base_url     = base_url
      @http_timeout = http_timeout
      @user_agent   = user_agent
    end

    # Returns array of hashes: [{ name:, url:, price:, starts_on:, raw_data: }, ...]
    def call(html: nil)
      doc = html ? Nokogiri::HTML(html) : fetch_document(@base_url)
      parse_offers(doc)
    end

    private

    def default_user_agent
      "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    end

    def fetch_document(url)
      uri = URI.parse(url)
      req = Net::HTTP::Get.new(uri)
      req['User-Agent'] = @user_agent

      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == 'https',
        read_timeout: @http_timeout,
        open_timeout: @http_timeout
      ) do |http|
        res = http.request(req)
        raise "HTTP error: #{res.code}" unless res.is_a?(Net::HTTPSuccess)
        Nokogiri::HTML(res.body)
      end
    end

    def parse_offers(doc)
      doc.css(OFFER_CONTAINER_SELECTOR).map { |node| parse_offer(node) }.compact
    end

    def parse_offer(node)
      hotel_name = text_or_nil(node.at_css(HOTEL_NAME_SELECTOR))
      return nil if hotel_name.nil?

      href       = node.at_css('a')&.[]('href')
      url        = absolute_url(href)
      date_str   = node.to_html.scan(DATE_RANGE_REGEX).first
      price_text = text_or_nil(node.at_css(PRICE_SELECTOR))
      price      = to_decimal(price_text)

      {
        name: hotel_name,
        url: url,
        price: price,
        price_raw: price_text,
        starts_on: date_str,
        raw_data: collect_raw(node)
      }
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
        container_classes: node['class'],
        raw_text: squish(node.text),
        raw_html: node.to_html,
        detected_date: node.to_html.scan(DATE_RANGE_REGEX).first,
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
      s = str.gsub(/[^\d,.\-]/, '')
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
    rescue
      href
    end
  end
end


