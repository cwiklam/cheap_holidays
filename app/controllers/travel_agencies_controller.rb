# frozen_string_literal: true
class TravelAgenciesController < ApplicationController
  before_action :set_travel_agency, only: %i[show edit update destroy]

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


  private

  def set_travel_agency
    @travel_agency = TravelAgency.find(params[:id])
  end

  def travel_agency_params
    params.require(:travel_agency).permit(:name, :description, :url)
  end
end
