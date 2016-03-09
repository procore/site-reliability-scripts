#!/usr/bin/env ruby
#
# VMContainment Script - Use Security Groups to contain a Nova VM or an EC2 VM.
#
#
# This script uses the Openstack CLI rather than the Openstack SDK's. This is because AJ
# spent 3 hours trying to get `openstacksdk` and `python-neutronclient` SDK to work using SSL
# and than gave up.
#

SECURITY_GROUP_NAME = 'containment_security_group'

require 'thor'
require 'json'
require 'aws-sdk'

Aws.config.update({
  region: ENV['AWS_REGION'],
  credentials: Aws::Credentials.new(ENV['AWS_ACCESS_KEY_ID'], ENV['AWS_SECRET_ACCESS_KEY'])
})
EC2Resources = Aws::EC2::Resource.new()

class NovaContainment < Thor
  desc "contain NAME", "Contain the Nova VM NAME"
  def contain(name)
    nova_contain(name)
  end

  def nova_contain(name)
      groups_list = JSON.parse(`neutron security-group-list -f json`)
      already_exists = false
      groups_list.each do |group|
        if group["name"] == SECURITY_GROUP_NAME
          already_exists = true
        end
      end

      if !already_exists
        `neutron security-group-create #{SECURITY_GROUP_NAME}`
      end

      # Get an array for current security groups assigned to a VM
      current_secgroups = `nova list-secgroup #{name} | cut -d'|' -f3`
      current_secgroups = current_secgroups.split("\n")[3..-2].map{ |sg| sg.strip }

      # Remove all currently assigned security groups
      current_secgroups.each do |sg|
        `nova remove-secgroup #{name} #{sg}`
      end

      `nova add-secgroup #{name} #{SECURITY_GROUP_NAME}`
  end
end

class EC2Containment < Thor
  desc "contain ID", "Contain the EC2 Instance with ID"
  def contain(id)
    ec2_contain(id)
  end

  def ec2_contain(id)
    vm = EC2Resources.instance(id)
    containment_sg = nil

    already_exists = false
    EC2Resources.security_groups.each do |sg|
      if sg.group_name == SECURITY_GROUP_NAME && sg.vpc_id.nil?
        already_exists = true
        containment_sg = sg
      end
    end

    if !already_exists
      new_sg_params = {
        group_name: SECURITY_GROUP_NAME,
        description: "Security group for locking down a VM."
      }
      if !vm.vpc_id.nil?
        new_sg_params["vpc_id"] = vm.vpc_id
      end

      containment_sg = EC2Resources.create_security_group(new_sg_params)
    end

    # Remove all security groups
    vm.modify_attribute({groups: []})

    if containment_sg.nil?
      abort "Something went really wrong and the containment security group was not created."
    end

    # Add back only containement security group
    vm.modify_attribute({groups: [containment_sg.id]})

  end
end

class VMContainment < Thor
  desc "nova", "Command for containing Nova VM's"
  subcommand "nova", NovaContainment

  desc "ec2", "Command for containing EC2 VM's"
  subcommand "ec2", EC2Containment
end
