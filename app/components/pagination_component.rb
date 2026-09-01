# frozen_string_literal: true

class PaginationComponent < ViewComponent::Base
  def initialize(paginator:, per_page_options: [50, 100], current_per_page: 50)
    @paginator = paginator
    @per_page_options = Array(per_page_options).presence || [50, 100]
    @current_per_page = current_per_page
  end

  attr_reader :paginator, :per_page_options, :current_per_page
end
