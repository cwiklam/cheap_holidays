# == Schema Information
#
# Table name: travel_agencies
#
#  id            :integer          not null, primary key
#  name          :string           not null
#  description   :text
#  url           :string           not null
#  next_page_url :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#

# frozen_string_literal: true

FactoryBot.define do
  factory :travel_agency do
    name { "#{Faker::Company.unique.name}" }
    url { "https://#{Faker::Internet.unique.domain_word}.example.com" }
    next_page_url { '?page=' }
    description { Faker::Lorem.paragraph(sentence_count: 2) }

    trait :long_description do
      description { Faker::Lorem.paragraphs(number: 5).join("\n\n") }
    end
  end
end
