#!/usr/bin/env ruby
# frozen_string_literal: true

require 'aws-sdk-rds'
require 'pp'
require 'csv'
require 'optparse'

file = ARGV.pop
unless File.file?(file)
  puts "Did not find an input file #{file}. Creating a Template file of that name for you!"
  File.open(file, "w") {|f| f.write('AWS_Account,AWS_Region,ParameterGroupType,ParameterGroupName')}
  exit 0
end

def clone_cluster_parameter_group(client, source, target)
  resp = client.copy_db_cluster_parameter_group({
    source_db_cluster_parameter_group_identifier: source,
    target_db_cluster_parameter_group_identifier: target,
    target_db_cluster_parameter_group_description: 'Custom Cluster dB parameter group with Connection Logging',
  })
  if resp.db_cluster_parameter_group.db_cluster_parameter_group_name == target
    puts "Successfully created clone of Cluster dB ParameterGroup #{source} -> #{target}"
  else
    puts "Failed to create clone of Cluster dB ParameterGroups #{source} -> #{target}"
  end
end

def modify_cluster_parameter_group(client, target, family)
  resp = client.modify_db_cluster_parameter_group({
    db_cluster_parameter_group_name: target,
    parameters: [
      {
        apply_method: "immediate",
        parameter_name: "log_connections",
        parameter_value: "1",
        description: "Log connections to the Server",
        apply_type: "dynamic",
        data_type: "boolean",
        allowed_values: "0,1",
        is_modifiable: true,
        minimum_engine_version: "#{family}",
        supported_engine_modes: ["provisioned"],
        source: 'engine-default',
      },
      {
        apply_method: "immediate",
        parameter_name: "log_disconnections",
        parameter_value: "1",
        description: "Log disconnections to the Server",
        apply_type: "dynamic",
        data_type: "boolean",
        allowed_values: "0,1",
        is_modifiable: true,
        minimum_engine_version: "#{family}",
        supported_engine_modes: ["provisioned"],
        source: 'engine-default',
      },
      {
        apply_method: "pending-reboot",
        parameter_name: "track_activity_query_size",
        parameter_value: "10240",
        description: "Sets the size reserved for pg_stat_activity.current_query, in bytes.",
        apply_type: "static",
        data_type: "boolean",
        allowed_values: "100-102400",
        is_modifiable: true,
        minimum_engine_version: "#{family}",
        supported_engine_modes: ["provisioned"],
        source: 'engine-default',
      },
      {
        apply_method: "pending-reboot",
        parameter_name: "shared_preload_libraries",
        parameter_value: "pg_stat_statements",
        description: "Lists shared libraries to preload into server.",
        apply_type: "static",
        data_type: "list",
        allowed_values: "auto_explain,orafce,pgaudit,pg_similarity,pg_stat_statements,pg_hint_plan",
        is_modifiable: true,
        minimum_engine_version: "#{family}",
        supported_engine_modes: ["provisioned"],
      }
    ]
  })
  if resp.db_cluster_parameter_group_name == target
    puts "Modified Cluster dB ParameterGroup #{resp.db_cluster_parameter_group_name}"
  else
    puts "Failed to modify Cluster dB Parameter Group for #{resp.db_cluster_parameter_group_name}"
  end
end

def clone_and_modify_instance_parameter_group(client, source, target, family)
  resp = client.copy_db_parameter_group({
    source_db_parameter_group_identifier: source,
    target_db_parameter_group_identifier: target,
    target_db_parameter_group_description: "Procore Paramaters with Connection Logging Enabled",
  })

  if resp.db_parameter_group.db_parameter_group_name == target
    puts "Successfully cloned Instance ParameterGroup #{source} to #{target}"

    resp = client.modify_db_parameter_group({
      db_parameter_group_name: target,
      parameters: [
        {
          apply_method: "immediate",
          parameter_name: "log_connections",
          parameter_value: "1",
          description: "Log successful connections to the server",
          apply_type: "dynamic",
          data_type: "boolean",
          allowed_values: "0,1",
          is_modifiable: true,
          minimum_engine_version: "#{family}",
          supported_engine_modes: ["provisioned"],
        },
        {
          apply_method: "immediate",
          parameter_name: "log_disconnections",
          parameter_value: "1",
          description: "Log disconnections from the Server",
          apply_type: "dynamic",
          data_type: "boolean",
          allowed_values: "0,1",
          is_modifiable: true,
          minimum_engine_version: "#{family}",
          supported_engine_modes: ["provisioned"],
        },
        {
          apply_method: "pending-reboot",
          parameter_name: "track_activity_query_size",
          parameter_value: "10240",
          description: "Sets the size reserved for pg_stat_activity.current_query, in bytes.",
          apply_type: "static",
          data_type: "boolean",
          allowed_values: "100-102400",
          is_modifiable: true,
          minimum_engine_version: "#{family}",
          supported_engine_modes: ["provisioned"],
          source: 'engine-default',
        },
        {
          apply_method: "pending-reboot",
          parameter_name: "shared_preload_libraries",
          parameter_value: "pg_stat_statements",
          description: "Lists shared libraries to preload into server.",
          apply_type: "static",
          data_type: "list",
          allowed_values: "auto_explain,orafce,pgaudit,pg_similarity,pg_stat_statements,pg_hint_plan",
          is_modifiable: true,
          minimum_engine_version: "#{family}",
          supported_engine_modes: ["provisioned"],
        }
      ],
    })
    if resp.db_parameter_group_name == target
      puts "Modified Instance Parameter Group for #{resp.db_parameter_group_name}"
    else
      puts "Failed to modify dB instance Parameter Group #{resp.db_parameter_group_name}"
    end
  end
end

# Normalize the names of the target ParameterGroups
# - remove references to "default"
# - prefix Cluster PG with pg-clstr-
def normalize_cluster_name(cluster_name)
  new_name = ''
  if cluster_name.match?('default.')
    new_name = cluster_name.sub('default.', 'pg-clstr-')
  else
    new_name = "pg-clstr-#{cluster_name}"
  end
  new_name
end

# Normalize the names of the target ParameterGroups
# - prefix for the instance ParameterGroups with pg-
def normalize_instance_name(instance_name)
  new_name = ''
  if instance_name.match?('default.')
    new_name = instance_name.sub('default.', 'pg-')
  else
    new_name = "pg-#{instance_name}"
  end
  new_name
end

def get_family_from_parameter_group(client, cluster_name)
  resp = client.describe_db_cluster_parameter_groups({
    db_cluster_parameter_group_name: cluster_name,
  })
  family_number = resp.db_cluster_parameter_groups[0].db_parameter_group_family.scan(/(\d+\.\d+)/).first[0]
  family_number
end

CSV.foreach(file, headers: true) do |row|
  profile = row[0]
  region = row[1]
  param_type = row[2]
  source = row[3]

  client =  Aws::RDS::Client.new(region: region, profile: profile)

  case (param_type)
  when 'cluster'
    target = normalize_cluster_name(source)
    family = get_family_from_parameter_group(client, source)
    clone_cluster_parameter_group(client, source, target)
    modify_cluster_parameter_group(client, target, family)
  when 'instance'
    target = normalize_instance_name(source)
    clone_and_modify_instance_parameter_group(client, source, target, family)
  end
end

