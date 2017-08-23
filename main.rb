require 'bundler/setup'
require 'aws-sdk-core'
require 'logger'

$stdout.sync = true

Log = Logger.new(STDOUT)

AsgClient = Aws::AutoScaling::Client.new(
  access_key_id: ENV['AWS_ACCESS_KEY_ID'],
  secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
)

Log.info("starting... #{ARGV}")

GROUP_NAME = ARGV[0]

def get_group
  AsgClient.describe_auto_scaling_groups(auto_scaling_group_names: [GROUP_NAME]).auto_scaling_groups[0]
end

group = get_group()

terminated = {}

desired = group.desired_capacity
minimum = group.min_size
maximum = group.max_size
desired_lc = group.launch_configuration_name
old_instances = group.instances.select { |inst| inst.launch_configuration_name != desired_lc }
old_count = old_instances.count

Log.info("starting with config: max=#{maximum} min=#{minimum} old=#{old_count} desired=#{desired} desired_lc=#{desired_lc}")

# Update the autoscaling group to make the desired capacity the maximum. We'll change this
# back after the update is finished, but this immediately launches more fresh machines which
# speeds up the process.
if desired < maximum
  Log.info("update group: desired=#{maximum}")
  AsgClient.update_auto_scaling_group(
    auto_scaling_group_name: GROUP_NAME, 
    max_size: maximum,
    min_size: minimum,
    desired_capacity: maximum,
  )
end

while old_count > 0
  # Fetch the group directly from the API every iteration. We then calculate various vars.
  group = get_group()
  ready_count = group.instances.count { |inst| inst.lifecycle_state == 'InService' }
  pending_count = group.instances.count { |inst| inst.lifecycle_state == 'Pending' }
  total_count = group.instances.count
  old_instances = group.instances.select { |inst| inst.launch_configuration_name != desired_lc }
  old_count = old_instances.count

  # For the difference in ready instances and the minimum, we remove all the old instances
  # that we can.
  (ready_count - minimum).times do |i|
    # Count may not be reflective
    break unless old_instances[i]

    # Select an instance by index to terminate. Since the ordering returned by the autoscaling
    # endpoint seems to be consistent we shouldn't kill multiple instances in a row here.
    to_terminate = old_instances[i].instance_id

    # Sometimes it takes a 10 - 20 seconds for a terminated instance to vanish. Also we could
    # have more space to remove instances than need to be removed.
    break unless to_terminate && !terminated[to_terminate]
    terminated[to_terminate] = true

    # Terminate the instance, since we don't decrement the capacity AWS will replace this instance.
    Log.info("terminating instance #{to_terminate}")
    AsgClient.terminate_instance_in_auto_scaling_group({
      instance_id: to_terminate, 
      should_decrement_desired_capacity: false, 
    })
  end

  # Log some state and sleep between iterations.
  Log.info("pending=#{pending_count} ready=#{ready_count} old=#{old_count}")
  sleep(5)
end

# Return to the previous configuration.
if desired < maximum
  AsgClient.update_auto_scaling_group(
    auto_scaling_group_name: GROUP_NAME, 
    max_size: maximum,
    min_size: minimum,
    desired_capacity: desired,
  )
end

Log.info("finished!")
