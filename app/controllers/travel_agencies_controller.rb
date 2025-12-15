# frozen_string_literal: true
class TravelAgenciesController < ApplicationController
  before_action :set_travel_agency, only: %i[show edit update destroy fetch]

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

  # Triggers background fetching pipeline depending on agency type
  def fetch
    query     = params[:q].to_s.strip.presence
    max_pages = params[:max_pages]&.to_i

    case @travel_agency.name_id
    when 'itaka'
      TravelAgencies::ItakaSequentialFetchJob.perform_later(page: 1, query: query, max_pages: max_pages)
    when 'tui'
      TravelAgencies::TuiSequentialFetchJob.perform_later(page: 1, query: query, max_pages: max_pages)
    else
      redirect_to @travel_agency, alert: "Fetch not implemented for agency: #{@travel_agency.name_id}" and return
    end

    redirect_to @travel_agency, notice: 'Fetch job enqueued. Offers will be processed in background.'
  end


  private

  def set_travel_agency
    @travel_agency = TravelAgency.find(params[:id])
  end

  def travel_agency_params
    params.require(:travel_agency).permit(:name, :name_id, :description, :url)
  end
end
