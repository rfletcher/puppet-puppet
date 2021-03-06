# Class: puppet::passenger
#
# This class installs and configures the puppetdb terminus pacakge
#
# Parameters:
#   ['generate_ssl_certs']       - Generate ssl certs (false to disable)
#   ['puppet_passenger_port']    - The port for the virtual host
#   ['puppet_docroot']           - Apache documnet root
#   ['apache_serveradmin']       - The apache server admin
#   ['puppet_conf']              - The puppet config dir
#   ['puppet_ssldir']            - The pupet ssl dir
#   ['certname']                 - The puppet certname
#   ['conf_dir']                 - The configuration directory of the puppet install
#
# Actions:
# - Configures apache and passenger for puppet master use.
#
# Requires:
# - Inifile
# - Class['puppet::params']
# - Class['apache']
#
# Sample Usage:
#   class { 'puppet::passenger':
#           puppet_passenger_port  => 8140,
#           puppet_docroot         => '/etc/puppet/docroot',
#           apache_serveradmin     => 'wibble',
#           puppet_conf            => '/etc/puppet/puppet.conf',
#           puppet_ssldir          => '/var/lib/puppet/ssl',
#           certname               => 'puppet.example.com',
#           conf_dir               => '/etc/puppet',
#   }
#

class puppet::passenger(
  $apache_serveradmin,
  $certname,
  $dns_alt_names,
  $generate_ssl_certs = true,
  $pool_size = floor( $::processorcount * 1.5 ),
  $puppet_conf,
  $puppet_docroot,
  $puppet_passenger_port,
  $puppet_passenger_tempdir = false,
  $puppet_root,
  $puppet_ssldir,
  $ca_server,
  $ca_port,
){
  include apache::modules::headers
  include apache::modules::passenger
  include apache::modules::ssl

  if $ca_server != undef and $ca_server != "" {
    include apache::modules::proxy
  }

  exec { "mkdir -p ${puppet_docroot}":
    creates => $puppet_docroot,
  } ->

  file { $puppet_docroot:
    ensure => directory,
    owner  => $::puppet::params::puppet_user,
    group  => $::puppet::params::puppet_group,
    mode   => '0755',
  } ->

  exec { 'puppermaster-passenger-install-config.ru':
    command => "cp ${puppet_root}/ext/rack/config.ru ${puppet_docroot}/../config.ru",
    creates => "${puppet_docroot}/../config.ru",
    notify  => $apache::manage_service_autorestart,
  } ->

  file_line { 'puppermaster-passenger-set-load_path':
    path   => "${puppet_docroot}/../config.ru",
    line   => '$LOAD_PATH.unshift(\'/usr/lib/ruby/vendor_ruby\')',
    after  => '^#\s+\$LOAD_PATH\.',
    notify => $apache::manage_service_autorestart,
  } ->

  file { "${puppet_docroot}/../config.ru":
    ensure => present,
    owner  => $::puppet::params::puppet_user,
    group  => $::puppet::params::puppet_group,
    mode   => '0644',
    notify => $apache::manage_service_autorestart,
  } ->

  apache::vhost { 'puppetmaster':
    content => template( 'puppet/puppet_passenger.conf.erb' ),
    require => Exec['Certificate_Check'],
  }

  if $::osfamily == 'redhat' {
    file { '/var/lib/puppet/reports':
      ensure => directory,
      owner  => $::puppet::params::puppet_user,
      group  => $::puppet::params::puppet_group,
    }
  }

  if str2bool( $generate_ssl_certs ) == true {
    file { "${puppet_ssldir}/ca":
      ensure => directory,
      owner  => $::puppet::params::puppet_user,
      group  => $::puppet::params::puppet_group,
      before => Exec['Certificate_Check'],
    }

    file{"${puppet_ssldir}/ca/requests":
      ensure => directory,
      owner  => $::puppet::params::puppet_user,
      group  => $::puppet::params::puppet_group,
      before => Exec['Certificate_Check'],
    }

    # first we need to generate the cert
    # Clean the installed certs out ifrst
    $crt_clean_cmd = "puppet cert clean ${certname}"
    # I would have preferred to use puppet cert generate, but it does not
    # return the corret exit code on some versions of puppet
    $crt_gen_cmd   = "puppet cert generate --dns_alt_names \"${dns_alt_names}\" ${certname}"
    # find is required to move the cert into the certs directory which is
    # where it needs to be for puppetdb to find it
    $cert_find_cmd = "puppet certificate --ca-location=local find ${certname}"

    exec { 'Certificate_Check':
      command   => "${crt_clean_cmd} ; ${crt_gen_cmd} && ${cert_find_cmd}",
      creates   => "${puppet_ssldir}/certs/${certname}.pem",
      logoutput => on_failure,
      require   => File[$::puppet::params::puppet_conf]
    }
  }

  ini_setting {'puppetmastersslclient':
    ensure  => present,
    section => 'master',
    setting => 'ssl_client_header',
    path    => $::puppet::params::puppet_conf,
    value   => 'SSL_CLIENT_S_DN',
    require => File[$::puppet::params::puppet_conf],
  }

  ini_setting {'puppetmastersslclientverify':
    ensure  => present,
    section => 'master',
    setting => 'ssl_client_verify_header',
    path    => $::puppet::params::puppet_conf,
    value   => 'SSL_CLIENT_VERIFY',
    require => File[$::puppet::params::puppet_conf],
  }
}
