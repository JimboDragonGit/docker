unified_mode true
use 'partial/_base'
use 'partial/_service_base'

resource_name :docker_service_manager_execute
provides :docker_service_manager_execute

# Start the service
action :start do
  # enable ipv4 forwarding
  execute 'enable net.ipv4.conf.all.forwarding' do
    command '/sbin/sysctl net.ipv4.conf.all.forwarding=1'
    not_if '/sbin/sysctl -q -n net.ipv4.conf.all.forwarding | grep ^1$'
    action :run
  end

  # enable ipv6 forwarding
  execute 'enable net.ipv6.conf.all.forwarding' do
    command '/sbin/sysctl net.ipv6.conf.all.forwarding=1'
    not_if '/sbin/sysctl -q -n net.ipv6.conf.all.forwarding | grep ^1$'
    action :run
  end

  # Go doesn't support detaching processes natively, so we have
  # to manually fork it from the shell with &
  # https://github.com/docker/docker/issues/2758
  bash "start docker #{new_resource.instance}" do
    code "#{docker_daemon_cmd} >> #{new_resource.logfile} 2>&1 &"
    environment 'HTTP_PROXY' => new_resource.http_proxy,
                'HTTPS_PROXY' => new_resource.https_proxy,
                'NO_PROXY' => new_resource.no_proxy,
                'TMPDIR' => new_resource.tmpdir
    not_if do
      container_command = [
        "ps -ef | grep -v grep | grep",
        Shellwords.escape(docker_daemon_cmd)
      ].join(' ')
      container_is_present = Mixlib::ShellOut.new(container_command)
      container_is_present.run_command
      container_is_present.error!
      container_is_present.stdout.include?(Shellwords.escape(docker_daemon_cmd))
    end
    only_if do
      docker_check = [docker_cmd, "ps | head -n 1 | grep ^CONTAINER"].join(' ')
      container_is_present = Mixlib::ShellOut.new(container_command)
      container_is_present.run_command
      container_is_present.error? && !::File.exist?(new_resource.pidfile)
    end
    action :run
  end

  create_docker_wait_ready

  execute 'docker-wait-ready' do
    command "#{libexec_dir}/#{docker_name}-wait-ready"
  end
end

action :stop do
  execute "stop docker #{new_resource.instance}" do
    command "kill `cat #{new_resource.pidfile}` && while [ -e #{new_resource.pidfile} ]; do sleep 1; done"
    timeout 10
    only_if do
      docker_check = [docker_cmd, "ps | head -n 1 | grep ^CONTAINER"].join(' ')
      container_is_present = Mixlib::ShellOut.new(docker_check)
      container_is_present.run_command
      container_is_present.error!
      container_is_present.stdout.start_with?('CONTAINER') && ::File.exist?(new_resource.pidfile)
    end
  end
end

action :restart do
  action_stop
  action_start
end
