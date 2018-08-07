source "https://rubygems.org"

ruby ">= 2.2.8"

gem "sinatra", "~> 2.0.3"
gem "sinatra-contrib", "~> 2.0.3"

gem "activerecord", "~> 5.1.5"
gem "sinatra-activerecord", "~> 2.0.13"
gem "sqlite3"

gem "unicorn"
gem "json"

gem "pbkdf2-ruby"
gem "rotp"
gem "jwt"

# for tools/activate_totp.rb
gem "rqrcode"

# for testing
gem "rake"
gem "minitest"
gem "rack-test"

group :keepass, :optional => true do
  gem 'rubeepass', '~> 3.0'
end

group :migrate, optional: true do
  gem 'yaml_db'
end

gem 'pry'
