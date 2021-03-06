FactoryBot.define do
  Faker::Config.locale = :en

  factory :phone_configuration do
    confirmed_at Time.zone.now
    phone '+1 202-555-1212'
    user
  end
end
