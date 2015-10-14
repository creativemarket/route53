
def name
  @name ||= begin
    return new_resource.name + '.' if new_resource.name !~ /\.$/
    new_resource.name
  end
end

def value
  @value ||= Array(new_resource.value)
end

def type
  @type ||= new_resource.type
end

def ttl
  @ttl ||= new_resource.ttl
end

def alias_target
  @alias_target ||= new_resource.alias_target
end

def health_check_id
  @health_check_id ||= new_resource.health_check_id
end

def failover
  @failover ||= new_resource.failover
end

def set_identifier
  @set_identifier ||= new_resource.set_identifier
end

def overwrite?
  @overwrite ||= new_resource.overwrite
end

def mock?
  @mock ||= new_resource.mock
end

def zone_id
  @zone_id ||= new_resource.zone_id
end

def route53
  @route53 ||= begin
    if mock?
      @route53 = Aws::Route53::Client.new(stub_responses: true)
    elsif new_resource.aws_access_key_id && new_resource.aws_secret_access_key
      @route53 = Aws::Route53::Client.new(
        access_key_id: new_resource.aws_access_key_id,
        secret_access_key: new_resource.aws_secret_access_key,
        region: new_resource.aws_region
      )
    else
      Chef::Log.info "No AWS credentials supplied, going to attempt to use automatic credentials from IAM or ENV"
      @route53 = Aws::Route53::Client.new(
        region: new_resource.aws_region
      )
    end
  end
end

def value_record_set
  {
    name: name,
    type: type,
    ttl: ttl,
    resource_records:
      value.sort.map{|v| {value: v} }
  }
end

def alias_record_set
  {
    name: name,
    type: type,
    set_identifier: set_identifier,
    failover: failover,
    alias_target: alias_target
  }
end

def current_value_record_set
  # List all the resource records for this zone:
  lrrs = route53.
    list_resource_record_sets(
      hosted_zone_id: "/hostedzone/#{zone_id}",
      start_record_name: name
    )

  # Select current resource record set by name
  current = lrrs[:resource_record_sets].
    select{ |rr| rr[:name] == name }.first

  # return as hash, converting resource record
  # array of structs to array of hashes
  if current
    {
      name: current[:name],
      type: current[:type],
      ttl: current[:ttl],
      resource_records:
        current[:resource_records].sort.map{ |rrr| rrr.to_h }
    }
  else
    {}
  end
end

def current_alias_record_set
  # List all the resource records for this zone:
  lrrs = route53.
    list_resource_record_sets(
      hosted_zone_id: "/hostedzone/#{zone_id}",
      start_record_name: name
    )

  # Select current resource record set by name
  current = lrrs[:resource_record_sets].
    select{ |rr| rr[:name] == name && rr[:set_identifier] == set_identifier }.first

  # return as hash, converting resource record
  # array of structs to array of hashes
  if current
    {
      name: current[:name],
      type: current[:type],
      set_identifier: current[:set_identifier],
      failover: current[:failover],
      alias_target:
        current[:alias_target].to_h
    }
  else
    {}
  end
end

def change_record(action)
    begin
    if alias_target
        record_set = alias_record_set
    else
        record_set = value_record_set
    end

    request = {
        hosted_zone_id: "/hostedzone/#{zone_id}",
        change_batch: {
            comment: "Chef Route53 Resource: #{name}",
            changes: [
                {
                    action: action,
                    resource_record_set: record_set
                },
            ],
        },
    }

    if health_check_id
        request[:change_batch][:changes][0][:resource_record_set].merge!({ health_check_id: health_check_id })
    end
    response = route53.change_resource_record_sets(request)
    Chef::Log.debug "Changed record - #{action}: #{response.inspect}"
    rescue Aws::Route53::Errors::ServiceError => e
    Chef::Log.error "Error with #{action}request: #{request.inspect}"
    Chef::Log.error e.message
    end
end

def push_changes
    if overwrite?
      change_record "UPSERT"
      Chef::Log.info "Record created/modified: #{name}"
    else
      change_record "CREATE"
      Chef::Log.info "Record created: #{name}"
    end
end

action :create do
  require 'aws-sdk'

  case alias_target
  when nil
      Chef::Log.debug "current_value_record_set = #{current_value_record_set}"
      Chef::Log.debug "value_record_set = #{value_record_set}"
      if current_value_record_set == value_record_set
        Chef::Log.debug "Current resources match specification"
      else
          push_changes
      end
  else
      Chef::Log.debug "current_alias_record_set = #{current_alias_record_set}"
      Chef::Log.debug "alias_record_set = #{alias_record_set}"
      if current_alias_record_set == alias_record_set
        Chef::Log.debug "Current resources match specification"
      else
        push_changes
      end
  end
end

action :delete do
  require 'aws-sdk'

  if mock?
    mock_resource_record_set = {
      :name=>"www.mock.com.",
      :type=>"A",
      :ttl=>300,
      :resource_records=>[{:value=>"192.168.1.2"}]
    }

    route53.stub_responses(
      :list_resource_record_sets,
      { resource_record_sets: [ mock_resource_record_set ] }
    )

  end

  if current_value_record_set.nil? && current_alias_record_set.nil?
    Chef::Log.info 'There is nothing to delete.'
  else
    change_record "DELETE"
    Chef::Log.info "Record deleted: #{name}"
  end
end
