# This script prints all US IP Ranges for EC2, S3, and generic AMAZON services
require 'net/http'
require 'json'

res = JSON.parse(Net::HTTP.get(URI('https://ip-ranges.amazonaws.com/ip-ranges.json')))

us_ip_ranges = []
res["prefixes"].each do |prefix|
  if prefix["region"].start_with?("us-")
    if ["EC2", "S3", "AMAZON"].include?(prefix["service"])
      us_ip_ranges << prefix["ip_prefix"]
    end
  end
end
puts us_ip_ranges
