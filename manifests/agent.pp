# Class: puppet::agent
#
# This class installs and configures the puppet agent
#
# Parameters:
#   ['puppet_server']         - The dns name of the puppet master
#   ['puppet_server_port']    - The Port the puppet master is running on
#   ['puppet_agent_service']  - The service the puppet agent runs under
#   ['puppet_agent_package']  - The name of the package providing the puppet agent
#   ['version']               - The version of the puppet agent to install
#   ['puppet_run_style']      - The run style of the agent either 'service', 'cron', 'external' or 'manual'
#   ['puppet_run_interval']   - The run interval of the puppet agent in minutes, default is 30 minutes
#   ['puppet_run_command']    - The command that will be executed for puppet agent run
#   ['user_id']               - The userid of the puppet user
#   ['group_id']              - The groupid of the puppet group
#   ['splay']                 - If splay should be enable defaults to false
#   ['environment']           - The environment of the puppet agent
#   ['report']                - Whether to return reports
#   ['pluginsync']            - Whethere to have pluginsync
#   ['use_srv_records']       - Whethere to use srv records
#   ['srv_domain']            - Domain to request the srv records
#   ['ordering']              - The way the agent processes resources. New feature in puppet 3.3.0
#   ['trusted_node_data']     - Enable the trusted facts hash
#   ['listen']                - If puppet agent should listen for connections
#   ['reportserver']          - The server to send transaction reports to.
#   ['digest_algorithm']      - The algorithm to use for file digests.
#   ['templatedir']           - Template dir, if unset it will remove the setting.
#   ['configtimeout']         - How long the client should wait for the configuration to be retrieved before considering it a failure
#   ['stringify_facts']       - Wether puppet transforms structured facts in strings or no. Defaults to true in puppet < 4, deprecated in puppet >=4 (and will default to false)
#   ['http_proxy_host']       - The hostname of an HTTP proxy to use for agent -> master connections
#   ['http_proxy_port']       - The port to use when puppet uses an HTTP proxy
#   ['server_pool_size']      - Number of puppet master servers. Used to coarsely distribute load.
#
# Actions:
# - Install and configures the puppet agent
#
# Requires:
# - Inifile
#
# Sample Usage:
#   class { 'puppet::agent':
#       puppet_server             => master.puppetlabs.vm,
#       environment               => production,
#       splay                     => true,
#   }
#
class puppet::agent(
  $puppet_agent_service   = $::puppet::params::puppet_agent_service,
  $puppet_agent_package   = $::puppet::params::puppet_agent_package,
  $version                = 'present',
  $puppet_run_style       = 'service',
  $puppet_run_command     = 'puppet agent --no-daemonize --onetime --logdest syslog > /dev/null 2>&1',
  $user_id                = undef,
  $group_id               = undef,

  #[main]
  $templatedir            = undef,
  $syslogfacility         = undef,
  $priority               = undef,

  #[agent]
  $srv_domain             = undef,
  $ordering               = undef,
  $trusted_node_data      = undef,
  $environment            = undef,
  $puppet_server          = $::puppet::params::puppet_server,
  $use_srv_records        = undef,
  $puppet_run_interval    = undef,
  $splay                  = undef,
  $puppet_server_port     = $::puppet::params::puppet_server_port,
  $report                 = undef,
  $pluginsync             = undef,
  $listen                 = undef,
  $reportserver           = undef,
  $digest_algorithm       = $::puppet::params::digest_algorithm,
  $configtimeout          = undef,
  $stringify_facts        = undef,
  $verbose                = undef,
  $agent_noop             = undef,
  $usecacheonfailure      = undef,
  $certname               = undef,
  $http_proxy_host        = undef,
  $http_proxy_port        = undef,
  $server_pool_size       = undef,
) inherits puppet::params {

  if ! defined(User[$::puppet::params::puppet_user]) {
    user { $::puppet::params::puppet_user:
      ensure => present,
      uid    => $user_id,
      gid    => $::puppet::params::puppet_group,
    }
  }

  if ! defined(Group[$::puppet::params::puppet_group]) {
    group { $::puppet::params::puppet_group:
      ensure => present,
      gid    => $group_id,
    }
  }
  package { $puppet_agent_package:
    ensure   => $version,
  }

  if $puppet_run_style == 'service' {
    $startonboot = 'yes'
  }
  else {
    $startonboot = 'no'
  }

  if ($::osfamily == 'Debian' and $puppet_run_style != 'manual') or ($::osfamily == 'Redhat') {
    file { $puppet::params::puppet_defaults:
      mode    => '0644',
      owner   => 'root',
      group   => 'root',
      require => Package[$puppet_agent_package],
      content => template("puppet/${puppet::params::puppet_defaults}.erb"),
    }
  }

  if ! defined(File[$::puppet::params::confdir]) {
    file { $::puppet::params::confdir:
      ensure  => directory,
      require => Package[$puppet_agent_package],
      owner   => $::puppet::params::puppet_user,
      group   => $::puppet::params::puppet_group,
      mode    => '0655',
    }
  }

  case $puppet_run_style {
    'service': {
      $service_ensure = 'running'
      $service_enable = true
    }
    'cron': {
      # ensure that puppet is not running and will start up on boot
      $service_ensure = 'stopped'
      $service_enable = false

      # Run puppet as a cron - this saves memory and avoids the whole problem
      # where puppet locks up for no reason. Also spreads out the run times
      # more uniformly.
      $time1  =  fqdn_rand($puppet_run_interval)
      $time2  =  fqdn_rand($puppet_run_interval) + 30

      cron { 'puppet-client':
        command => $puppet_run_command,
        user    => 'root',
        # run twice an hour, at a random minute in order not to collectively stress the puppetmaster
        hour    => '*',
        minute  => [ $time1, $time2 ],
      }
    }
    # Run Puppet through external tooling, like MCollective
    'external': {
      $service_ensure = 'stopped'
      $service_enable = false
    }
    # Do not manage the Puppet service and don't touch Debian's defaults file.
    manual: {
      $service_ensure = undef
      $service_enable = undef
    }
    default: {
      err('Unsupported puppet run style in Class[\'puppet::agent\']')
    }
  }

  if $puppet_run_style != 'manual' {
    service { $puppet_agent_service:
      ensure     => $service_ensure,
      enable     => $service_enable,
      hasstatus  => true,
      hasrestart => true,
      subscribe  => [File[$::puppet::params::puppet_conf], File[$::puppet::params::confdir]],
      require    => Package[$puppet_agent_package],
    }
  }

  if ! defined(File[$::puppet::params::puppet_conf]) {
      file { $::puppet::params::puppet_conf:
        ensure  => 'file',
        mode    => '0644',
        require => File[$::puppet::params::confdir],
        owner   => $::puppet::params::puppet_user,
        group   => $::puppet::params::puppet_group,
      }
    }
    else {
      if $puppet_run_style == 'service' {
        File<| title == $::puppet::params::puppet_conf |> {
          notify  +> Service[$puppet_agent_service],
        }
      }
    }

  #run interval in seconds
  $runinterval = "${puppet_run_interval}m"

  Ini_setting {
      path    => $::puppet::params::puppet_conf,
      require => File[$::puppet::params::puppet_conf],
      section => 'agent',
  }

  if (($use_srv_records == true) and ($srv_domain == undef))
  {
    fail("${module_name} has attribute use_srv_records set but has srv_domain unset")
  }
  elsif (($use_srv_records == true) and ($srv_domain != undef))
  {
    ini_setting {'puppetagentsrv_domain':
      ensure  => present,
      setting => 'srv_domain',
      value   => $srv_domain,
    }
  }
  elsif($use_srv_records == false)
  {
    ini_setting {'puppetagentsrv_domain':
      ensure  => absent,
      setting => 'srv_domain',
    }
  }

  ini_setting {'puppetagentordering':
    ensure  => $ordering ? { undef => absent, default => present },
    setting => 'ordering',
    value   => $ordering,
  }

  ini_setting {'puppetagenttrusted_node_data':
    ensure  => $trusted_node_data ? { undef => absent, default => present },
    setting => 'trusted_node_data',
    value   => $trusted_node_data,
  }

  ini_setting {'puppetagentenvironment':
    ensure  => $environment ? { undef => absent, default => present },
    setting => 'environment',
    value   => $environment,
  }

  if is_integer( $server_pool_size ) and $server_pool_size > 1 {
    $real_puppet_server = rand_hostname( $puppet_server, $server_pool_size )
  } else {
    $real_puppet_server = $puppet_server
  }

  ini_setting {'puppetagentmaster':
    ensure  => $puppet_server_port ? { undef => absent, 'puppet' => absent, default => present },
    setting => 'server',
    value   => $real_puppet_server,
  }

  ini_setting {'puppetagentuse_srv_records':
    ensure  => $use_srv_records ? { undef => absent, default => present },
    setting => 'use_srv_records',
    value   => $use_srv_records,
  }

  if $puppet_run_style == 'service' {
    $runinterval_ensure = undef
  } else {
    $runinterval_ensure = $runinterval_ensure ? {
      undef   => absent,
      '30m'   => absent,
      default => present
    }
  }

  ini_setting {'puppetagentruninterval':
    ensure  => $runinterval_ensure,
    setting => 'runinterval',
    value   => $runinterval,
  }

  ini_setting {'puppetagentsplay':
    ensure  => $splay ? { undef => absent, default => present },
    setting => 'splay',
    value   => $splay,
  }

  ini_setting {'puppetmasterport':
    ensure  => $puppet_server_port ? { undef => absent, '8140' => absent, default => present },
    setting => 'masterport',
    value   => $puppet_server_port,
  }

  ini_setting {'puppetagentreport':
    ensure  => $report ? { undef => absent, default => present },
    setting => 'report',
    value   => $report,
  }

  ini_setting {'puppetagentpluginsync':
    ensure  => $pluginsync ? { undef => absent, default => present },
    setting => 'pluginsync',
    value   => $pluginsync,
  }

  ini_setting {'puppetagentlisten':
    ensure  => $listen ? { undef => absent, default => present },
    setting => 'listen',
    value   => $listen,
  }

  ini_setting {'puppetagentreportserver':
    ensure  => $reportserver ? { undef => absent, default => present },
    setting => 'reportserver',
    value   => $reportserver,
  }

  ini_setting {'puppetagentdigestalgorithm':
    ensure  => $digest_algorithm ? { undef => absent, 'md5' => absent, default => present },
    setting => 'digest_algorithm',
    value   => $digest_algorithm,
  }

  ini_setting {'puppetagenttemplatedir':
    ensure  =>  $templatedir ? { undef => absent, default => present },
    setting => 'templatedir',
    section => 'main',
    value   => $templatedir,
  }

  ini_setting {'puppetagentconfigtimeout':
    ensure  => $configtimeout ? { undef => absent, default => present },
    setting => 'configtimeout',
    value   => $configtimeout,
  }

  ini_setting {'puppetagentstringifyfacts':
    ensure  => $stringify_facts ? { undef => absent, default => present },
    setting => 'stringify_facts',
    value   => $stringify_facts,
  }

  ini_setting {'puppetagentverbose':
    ensure  => $verbose ? { undef => absent, default => present },
    setting => 'verbose',
    value   => $verbose,
  }

  ini_setting {'puppetagentnoop':
    ensure  => $agent_noop ? { undef => absent, default => present },
    setting => 'noop',
    value   => $agent_noop,
  }

  ini_setting {'puppetagentusecacheonfailure':
    ensure  => $usecacheonfailure ? { undef => absent, default => present },
    setting => 'usecacheonfailure',
    value   => $usecacheonfailure,
  }

  ini_setting {'puppetagentsyslogfacility':
    ensure  => $syslogfacility ? { undef => absent, default => present },
    setting => 'syslogfacility',
    value   => $syslogfacility,
    section => 'main',
  }

  ini_setting {'puppetagentcertname':
    ensure  => $certname ? { undef => absent, default => present },
    setting => 'certname',
    value   => $certname,
  }

  ini_setting {'puppetagentpriority':
    ensure  => $priority ? { undef => absent, default => present },
    setting => 'priority',
    value   => $priority,
    section => 'main',
  }

  ini_setting {'puppetagenthttpproxyhost':
    ensure  => $http_proxy_host ? { undef => absent, default => present },
    setting => 'http_proxy_host',
    value   => $http_proxy_host,
  }

  ini_setting {'puppetagenthttpproxyport':
    ensure  => $http_proxy_port ? { undef => absent, default => present },
    setting => 'http_proxy_port',
    value   => $http_proxy_port,
  }
}
