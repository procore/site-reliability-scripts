#
# security_group_exporter exports all of the security groups and creates a script to re-import them (most likely into a new openstack deployment).
#
# Note: As of now, the script just ignores the `default` security group.
#
# Original Author: AJ Bahnken / ajvb
#

require 'json'
require 'fileutils'

# Create output folder
todays_date = Time.now.strftime "%Y-%m-%d"
FileUtils.mkdir("secgroup_exporter_#{todays_date}")

File.open("secgroup_exporter_#{todays_date}/importer.sh", "w") do |importer_script|
  importer_script.puts("#!/bin/bash")
  importer_script.puts("\n# *****************")
  importer_script.puts("# AUTO GENERATED SCRIPT")
  importer_script.puts("# *****************\n\n")

  # Pull in the list of security groups.
  groups_list = JSON.parse(`neutron security-group-list -f json`)

  groups_list.each do |group|
    # TODO: Check for rules
    if group["name"] == "default"
      next
    end

    secgroup_name = group["name"]

    group_details = JSON.parse(`neutron security-group-show #{secgroup_name} -f json`)

    importer_script.puts("# Start of #{secgroup_name} Rules")

    # Add the command to create the security group.
    sec_description = group_details[0]["Value"]
    if sec_description.nil?
      importer_script.puts("neutron security-group-create #{secgroup_name}")
    else
      importer_script.puts("neutron security-group-create #{secgroup_name} --description #{sec_description}")
    end

    # Parse out the actual rules. It requires a little bit of hackery because its not actually json.
    rules = JSON.parse('[' + group_details[3]["Value"].gsub(/}\n/, "},") + ']')

    rules.each do |rule|
      #$ neutron security-group-rule-create --direction ingress --ethertype IPv4 --protocol tcp --port-range-min 80 --port-range-max 80 --remote-ip-prefix 0.0.0.0/0 global_http
      importer_script.puts("neutron security-group-rule-create \\")
      rule.each do |key, val|
        unless val.nil?
          opt = key.gsub(/_/, "-")
          importer_script.puts("        --#{opt} #{val} \\")
        end
      end
      importer_script.puts("        #{secgroup_name}")
    end

    importer_script.puts("# End of #{secgroup_name} Rules\n\n")

  end
end
