# frozen_string_literal: true

require 'timeout'

# K8sConformanceTest represents the Kubernetes upstream conformance tests
class TestContainer
  def initialize(image, cluster, vpn_tunnel)
    @image = image
    @cluster = cluster
    @vpn_tunnel = vpn_tunnel
  end

  def run
    ::Timeout.timeout(3 * 60 * 60) do # 3 hours
      command = if @cluster.env_variables['PLATFORM'].include?('metal')
                  "sudo rkt run --volume kubecfg,kind=host,readOnly=false,source=#{@cluster.kubeconfig} \
                  --mount volume=kubecfg,target=/kubeconfig #{network_config} --dns=host \
                  #{container_env('rkt')} --insecure-options=image #{@image}"
                else
                  "docker run -v #{@cluster.kubeconfig}:/kubeconfig \
                  #{network_config} #{container_env('docker')} #{@image}"
                end

      succeeded = system(command)
      raise 'Running container tests failed' unless succeeded
    end
  end

  private

  # When the cluster is only reachable via a VPN connection, the
  # kube-conformance container has to share the same linux network namespace
  # like the current container to be able to use the same VPN tunnel.
  def network_config
    return '--net=host' unless @vpn_tunnel

    hostname = `hostname`.chomp
    "--net=container:#{hostname}"
  end

  # Some tests require a few environment variables to run properly,
  # build the environment parameters here.
  def container_env(engine)
    env = {
      'BRIDGE_AUTH_USERNAME' => @cluster.tectonic_admin_email,
      'BRIDGE_AUTH_PASSWORD' => @cluster.tectonic_admin_password,
      'BRIDGE_BASE_ADDRESS' => 'https://' + @cluster.tectonic_console_url,
      'BRIDGE_BASE_PATH' => '/'
    }

    return env.map { |k, v| "-e #{k}='#{v}'" }.join(' ').chomp if engine == 'docker'
    return env.map { |k, v| "--set-env #{k}='#{v}'" }.join(' ').chomp if engine == 'rkt'
    raise 'unknown container engine'
  end
end
