# What Fitora needs to start, and nothing else: no gym, no member, no sample data.
#
# Every deploy runs this (bin/docker-entrypoint), so it must stay safe to run
# again: it adds what is missing and never undoes what a superadmin has done
# since. Each file below says how it keeps to that.
puts "Seeding the platform settings..."
PlatformSetting.current

puts "Seeding the activity catalogue..."
load Rails.root.join("db/seeds/activity_templates.rb")

puts "Seeding the e-mail templates..."
load Rails.root.join("db/seeds/mail_templates.rb")

puts "Seeding the superadmin account..."
load Rails.root.join("db/seeds/superadmin.rb")

puts "Seed complete."
