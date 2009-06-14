require 'machinist/active_record'
require "sham"

Sham.name { (1..10).map { ('a'..'z').to_a.rand }.join }
Sham.login { (1..10).map { ('a'..'z').to_a.rand }.join }
Sham.full_name  { Faker::Name.name }
Sham.email { Faker::Internet.email }
Sham.title { Faker::Lorem.sentence }
Sham.body  { Faker::Lorem.paragraph }
Sham.description { Sham.body }

User.blueprint do
  login
  email
  password { "test" }
  password_confirmation { "test" }
end

Version.blueprint do
  name
  version { "1.0" }

  package
end

Package.blueprint do
  name
end

Author.blueprint do
  name { Sham.full_name }
  email
end

Review.blueprint do
  title
  review { Sham.body }
  rating { (1..5).to_a.rand }

  package
  user
end

Tag.blueprint do
  name
  full_name
  description
end