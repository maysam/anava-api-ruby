FactoryBot.define do
  factory :recording do
    user_id { Faker::Internet.uuid }
    model { %w[Pixel-7 iPhone-14 Galaxy-S23 OnePlus-11].sample }
    build { Faker::Internet.ip_v4_address }
    version { Faker::App.semantic_version }
    date { Faker::Date.backward(days: 30) }
    slot_id { rand(1..5) }
    amplitudes_json { Array.new(10) { rand(0..100) }.to_json }
    start_timestamp { rand(1_700_000_000_000..1_800_000_000_000) }
    end_timestamp { start_timestamp + rand(1_000..60_000) }
    longitude { Faker::Address.longitude }
    latitude { Faker::Address.latitude }
    duration { ((end_timestamp - start_timestamp) / 1000.0).floor }
    percentage { rand(0..100) }
    file_path { nil }
  end
end
