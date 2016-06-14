#!/usr/bin/env ruby

#
# OSMigrator - An Open Stack Migration Tool
#
# Original Author: AJ Bahnken / ajvb
#

require 'csv'
require 'fileutils'
require 'json'
require 'thor'

OUTPUT_FOLDER = "osmigrator_output"
FILE_NAMES = {
  flavors: 'flavor_export.csv',
  nodes: 'node_export.csv',
  secgroups: 'secgroup_importer.sh',
}

class Import < Thor
  desc "flavor", "Import flavors"
  def flavor
    flavor_import
  end

  desc "secgroup", "Import security groups"
  def secgroup
    secgroup_import
  end

  desc "all", "Import all"
  def all
    secgroup_import
    flavor_import
  end

  private

  def flavor_import
    CSV.foreach("#{OUTPUT_FOLDER}/#{FILE_NAMES[:flavors]}") do |row|
      # `nova flavor-create NAME ID RAM DISK_SIZE VCPUS --swap swap_in_mb`
      `nova flavor-create #{row[0]} #{row[1]} #{row[2]} #{row[3]} #{row[4]} --swap #{row[5]}`
    end
  end

  def secgroup_import
    importer_path = "#{OUTPUT_FOLDER}/#{FILE_NAMES[:secgroups]}"
    if File.exist?(importer_path)
      `cd #{OUTPUT_FOLDER} && bash #{FILE_NAMES[:secgroups]}`
    else
      puts "ERROR:"
      puts "Could not find importer script at: #{importer_path}"
    end
  end

end

class Export < Thor
  desc "nodes", "Export node definitions with flavor, image, and security groups"
  def nodes
    create_output_folder
    node_export
  end

  desc "flavor", "Export flavors"
  def flavor
    create_output_folder
    flavor_export
  end

  desc "secgroup", "Export security groups"
  def secgroup
    create_output_folder
    secgroup_export
  end

  desc "all", "Export all"
  def all
    create_output_folder
    secgroup_export
    flavor_export
    node_export
  end

  private

  def secgroup_export
    File.open("#{OUTPUT_FOLDER}/#{FILE_NAMES[:secgroups]}", "w") do |importer_script|
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
        sec_description = group_details["description"]
        if sec_description.nil?
          importer_script.puts("neutron security-group-create #{secgroup_name}")
        else
          importer_script.puts("neutron security-group-create #{secgroup_name} --description \"#{sec_description}\"")
        end

        # Parse out the actual rules. It requires a little bit of hackery because its not actually json.
        rules = JSON.parse('[' + group_details["security_group_rules"].gsub(/}\n/, "},") + ']')

        rules.each do |rule|
          #$ neutron security-group-rule-create --direction ingress --ethertype IPv4 --protocol tcp --port-range-min 80 --port-range-max 80 --remote-ip-prefix 0.0.0.0/0 global_http
          importer_script.puts("neutron security-group-rule-create \\")
          rule.each do |key, val|
            unless val.nil?
              opt = key.gsub(/_/, "-")
              # Skip over id's, as they will be different upon creation in the new OpenStack installation
              if opt == "id" or opt == "security-group-id"
                next
              end
              importer_script.puts("        --#{opt} #{val} \\")
            end
          end
          importer_script.puts("        #{secgroup_name}")
        end

        importer_script.puts("# End of #{secgroup_name} Rules\n\n")

      end
    end
  end

  def node_export
    deploy_script = File.open("#{OUTPUT_FOLDER}/node_deploy.sh", "w")
    deploy_script.puts("#!/bin/bash")
    deploy_script.puts("\n# *****************")
    deploy_script.puts("# AUTO GENERATED SCRIPT")
    deploy_script.puts("# *****************\n\n")
    CSV.open("#{OUTPUT_FOLDER}/#{FILE_NAMES[:nodes]}", "w",
             :col_sep => '|',
             :write_headers => true,
             :headers => ["node_name", "flavor-image", "raw-flavor", "raw-image", "security_groups"]) do |export|
      all_nodes = `nova list | grep SERVICE | cut -d'|' -f3 | sort -r`.split("\n").map{|n| n = n.strip }
      all_nodes.each do |node|
        # [flavor, image, security_groups]
        node_details = `nova show #{node} | grep -E '(flavor|image|security_groups)' | grep -v 'name' | cut -d'|' -f3`
        node_details = node_details.split("\n").map{ |r| r = r.split("(")[0].strip }

        # ["m1.medium", "trusty-image"] -> "trusty.medium"
        flavor_image = node_details[1].split('-')[0] + "." + node_details[0].split(".")[1]

        export << [node, flavor_image, node_details[0], node_details[1], node_details[2]]

        # Now create server deploy commands.
        deploy_script.puts("echo '***************'")
        deploy_script.puts("echo 'Now creating #{node} as a #{flavor_image}'")
        deploy_script.puts("echo '***************'")
        deploy_script.puts("server deploy #{node} #{flavor_image}")

        # Filter out security groups that contain the word `default`
        non_default_secgroups = node_details[2].split(', ').select{ |s| !s.include? 'default' }
        if non_default_secgroups.length > 0
          deploy_script.puts("echo '***************'")
          deploy_script.puts("echo 'Now adding security groups to #{node}'")
          deploy_script.puts("echo '***************'")
          non_default_secgroups.each do |secgroup|
            deploy_script.puts("nova add-secgroup #{node} #{secgroup}")
          end
        end

        # Add some extra padding for easier readability within the script.
        deploy_script.puts("\n")
        deploy_script.puts("\n")
      end
    end
    deploy_script.close
  end

  def flavor_export
    flavors = `nova flavor-list`.split("\n")[3..-2]
    # Clean up terminal output
    flavors = flavors.map do |f|
      f = f.split("|").map do |d|
        d = d.strip
      end
    end


    CSV.open("#{OUTPUT_FOLDER}/#{FILE_NAMES[:flavors]}", "w",
            :write_headers => true,
            :headers => ["name", "id", "ram", "disk", "vcpus", "swap"]) do |export|
      flavors.each do |flavor|
        export << [flavor[2], flavor[1], flavor[3], flavor[4], flavor[7], flavor[6]]
      end
    end
  end

  def create_output_folder
    begin
      FileUtils.mkdir(OUTPUT_FOLDER)
    rescue
    end
  end
end

class OSMigrator < Thor
  desc "export", "Command for exporting"
  subcommand "export", Export

  desc "import", "Command for importing"
  subcommand "import", Import
end

OSMigrator.start(ARGV)
