#!/usr/bin/env ruby

require File.realpath(File.dirname(__FILE__) + "/../lib/bitwarden_ruby.rb")
require "getoptlong"

def usage
  puts "usage: #{$0} -f data.1pif -u user@example.com"
  exit 1
end

username = nil
file = nil

begin
  GetoptLong.new(
    [ "--file", "-f", GetoptLong::REQUIRED_ARGUMENT ],
    [ "--user", "-u", GetoptLong::REQUIRED_ARGUMENT ],
  ).each do |opt,arg|
    case opt
    when "--file"
      file = arg

    when "--user"
      username = arg
    end
  end

rescue GetoptLong::InvalidOption
  usage
end

if !file || !username
  usage
end

u = User.find_by_email(username)
if !u
  raise "can't find existing User record for #{username.inspect}"
end

print "master password for #{u.email}: "
system("stty -echo")
password = STDIN.gets.chomp
system("stty echo")
print "\n"

if !u.has_password_hash?(Bitwarden.hashPassword(password, username))
  raise "master password does not match stored hash"
end

master_key = Bitwarden.makeKey(password, u.email)

to_save = {}
skipped = 0

File.read(file).split("\n").each do |line|
  next if line[0] != "{"
  i = JSON.parse(line)

  c = Cipher.new
  c.user_uuid = u.uuid
  c.type = Cipher::TYPE_LOGIN
  c.favorite = (i["openContents"] && i["openContents"]["faveIndex"])

  cdata = { "Name" => (i["title"].blank? ? "--" : i["title"]) }

  if i["createdAt"]
    c.created_at = Time.at(i["createdAt"].to_i)
  end
  if i["updatedAt"]
    c.updated_at = Time.at(i["updatedAt"].to_i)
  end

  case i["typeName"]
  when "passwords.Password"
    if i["location"].present?
      cdata["Uri"] = i["location"]
    end

  when "securenotes.SecureNote"
    c.type = Cipher::TYPE_NOTE
    cdata["SecureNote"] = { "Type" => 0 }

  when "wallet.computer.Router"
    cdata["Password"] = i["secureContents"]["wireless_password"]

  when "wallet.financial.CreditCard"
    c.type = Cipher::TYPE_CARD

    if i["secureContents"]["cardholder"].present?
      cdata["CardholderName"] = i["secureContents"]["cardholder"]
    end
    if i["secureContents"]["cardholder"].present?
      cdata["Brand"] = i["secureContents"]["type"]
    end
    if i["secureContents"]["ccnum"].present?
      cdata["Number"] = i["secureContents"]["ccnum"]
    end
    if i["secureContents"]["expiry_mm"].present?
      cdata["expMonth"] = i["secureContents"]["expiry_mm"]
    end
    if i["secureContents"]["expiry_yy"].present?
      cdata["expYear"] = i["secureContents"]["expiry_yy"]
    end
    if i["secureContents"]["cvv"].present?
      cdata["Code"] = i["secureContents"]["cvv"]
    end

  when "webforms.WebForm"
    if i["location"].present?
      cdata["Uri"] = i["location"]
    end

  when "identities.Identity",
  "system.folder.Regular",
  "wallet.computer.License"
    puts "skipping #{i["typeName"]} #{i["title"]}"
    skipped += 1
    next

  else
    raise "unimplemented: #{i["typeName"].inspect}"
  end

  puts "converting #{Cipher.type_s(c.type)} #{i["title"]}... "

  if i["secureContents"]
    if i["secureContents"]["notesPlain"].present?
      cdata["Notes"] = i["secureContents"]["notesPlain"]
    end

    if i["secureContents"]["password"].present?
      cdata["Password"] = i["secureContents"]["password"]
    end

    if i["secureContents"]["fields"]
      cdata["Fields"] = {}

      i["secureContents"]["fields"].each do |field|
        case field["designation"]
        when "username"
          if c.type == Cipher::TYPE_LOGIN && cdata["Username"].blank? &&
          field["value"].present?
            cdata["Username"] = field["value"]
          end

        when "password"
          if c.type == Cipher::TYPE_LOGIN && cdata["Password"].blank? &&
          field["value"].present?
            cdata["Password"] = field["value"]
          end

        else
          if field["name"].present? && field["value"].present?
            cdata["Fields"][field["name"]] = field["value"]
          end
        end
      end
    end
  end

  # encrypt all cdata contents
  cdata.each do |k,v|
    if v.is_a?(Hash)
      v.each do |kk,vv|
        cdata[k][kk] = u.encrypt_data_with_master_password_key(vv.to_s,
          master_key)
      end
    else
      cdata[k] = u.encrypt_data_with_master_password_key(v.to_s, master_key)
    end
  end

  c.data = cdata.to_json

  to_save[c.type] ||= []
  to_save[c.type].push c
end

puts ""

to_save.each do |k,v|
  puts "#{sprintf("% 4d", v.count)} #{Cipher.type_s(k)}" <<
    (v.count == 1 ? "" : "s")
end

if skipped > 0
  puts "#{sprintf("% 4d", skipped)} skipped"
end

print "ready to import? [Y/n] "
if STDIN.gets.to_s.match(/n/i)
  exit 1
end

imp = 0
Cipher.transaction do
  to_save.each do |k,v|
    v.each do |c|
      if !c.save
        raise "failed saving #{c.inspect}"
      end

      imp += 1
    end
  end
end

puts "successfully imported #{imp} item#{imp == 1 ? "" : "s"}"
