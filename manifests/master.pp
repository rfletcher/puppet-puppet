# Class: puppet::master
#
# This class installs and configures a Puppet master
#
# Parameters:
#  ['user_id']                  - The userid of the puppet user
#  ['group_id']                 - The groupid of the puppet group
#  ['modulepath']               - Module path to be served by the puppet master
#  ['manifest']                 - Manifest path
#  ['external_nodes']           - ENC script path
#  ['node_terminus']            - Node terminus setting, is overridden to 'exec' if external_nodes is set
#  ['hiera_config']             - Hiera config file path
#  ['environments']             - Which environment method (directory or config)
#  ['environmentpath']          - Puppet environment base path (use with environments directory)
#  ['reports']                  - Turn on puppet reports
#  ['storeconfigs']             - Use storedconfigs
#  ['storeconfigs_dbserver']    - Puppetdb server
#  ['storeconfigs_dbport']      - Puppetdb port
#  ['certname']                 - The certname the puppet master should use
#  ['autosign']                 - Auto sign agent certificates default false
#  ['reporturl']                - Url to send reports to, if reporting enabled
#  ['puppet_ssldir']            - Puppet sll directory
#  ['puppet_docroot']           - Doc root to be configured in apache vhost
#  ['puppet_vardir']            - Vardir used by puppet
#  ['puppet_passenger_port']    - Port to configure passenger on default 8140
#  ['puppet_master_package']    - Puppet master package
#  ['puppet_master_service']    - Puppet master service
#  ['version']                  - Version of the puppet master package to install
#  ['apache_serveradmin']       - Apache server admin
#  ['pluginsync']               - Enable plugin sync
#  ['parser']                   - Which parser to use
#  ['puppetdb_startup_timeout'] - The timeout for puppetdb
#  ['dns_alt_names']            - Comma separated list of alternative DNS names
#  ['digest_algorithm']         - The algorithm to use for file digests.
#  ['generate_ssl_certs']       - Generate ssl certs (false to disable)
#  ['strict_variables']         - Makes the parser raise errors when referencing unknown variables
#  ['ca_server']                - Proxy certificate requests to another server
#  ['ca_port']                  - CA server port
#
# Requires:
#
#  - inifile
#  - Class['puppet::params']
#  - Class[puppet::passenger]
#  - Class['puppet::storeconfigs']
#
# Sample Usage:
#
#  $modulepath = [
#    "/etc/puppet/modules/site",
#    "/etc/puppet/modules/dist",
#  ]
#
#  class { "puppet::master":
#    modulepath             => inline_template("<%= modulepath.join(':') %>"),
#    storeconfigs          => 'true',
#  }
#
class puppet::master (
  $user_id                    = undef,
  $group_id                   = undef,
  $modulepath                 = $::puppet::params::modulepath,
  $manifest                   = $::puppet::params::manifest,
  $external_nodes             = undef,
  $node_terminus              = undef,
  $hiera_config               = $::puppet::params::hiera_config,
  $environmentpath            = $::puppet::params::environmentpath,
  $environments               = $::puppet::params::environments,
  $reports                    = undef,
  $storeconfigs               = undef,
  $storeconfigs_dbserver      = $::puppet::params::storeconfigs_dbserver,
  $storeconfigs_dbport        = $::puppet::params::storeconfigs_dbport,
  $certname                   = $::fqdn,
  $autosign                   = undef,
  $reporturl                  = undef,
  $puppet_ssldir              = $::puppet::params::puppet_ssldir,
  $puppet_root                = $::puppet::params::puppet_root,
  $puppet_docroot             = $::puppet::params::puppet_docroot,
  $puppet_vardir              = $::puppet::params::puppet_vardir,
  $puppet_passenger_port      = $::puppet::params::puppet_passenger_port,
  $puppet_passenger_tempdir   = false,
  $puppet_master_package      = $::puppet::params::puppet_master_package,
  $puppet_master_service      = $::puppet::params::puppet_master_service,
  $version                    = 'present',
  $apache_serveradmin         = $::puppet::params::apache_serveradmin,
  $pluginsync                 = true,
  $parser                     = $::puppet::params::parser,
  $manage_puppetdb            = true,
  $puppetdb_startup_timeout   = '60',
  $puppetdb_strict_validation = $::puppet::params::puppetdb_strict_validation,
  $dns_alt_names              = undef,
  $digest_algorithm           = $::puppet::params::digest_algorithm,
  $generate_ssl_certs         = true,
  $strict_variables           = undef,
  $puppetdb_version           = 'present',
  $ca_server                  = undef,
  $ca_port                    = $::puppet::params::ca_port,
  $package_source             = undef,
  $common_package_source      = undef,
  $terminus_package_source    = undef,
) inherits puppet::params {
  include apache

  anchor { 'puppet::master::begin': }

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

  if $package_source != undef {
    if $terminus_package_source != undef {
      $terminus_package             = 'puppetdb-terminus'
      $real_terminus_package_source = '/tmp/puppetdb-terminus.deb'

      wget::fetch { $terminus_package:
        source      => $terminus_package_source,
        destination => $real_terminus_package_source,
        before      => Package[$terminus_package],
      }

      # remove any version previously installed with apt
      exec { "remove apt ${terminus_package}":
        command => "dpkg -r ${terminus_package}",
        onlyif  => "dpkg --list ${terminus_package} | grep '^i' && apt-cache madison ${terminus_package} | grep \"\$(dpkg-query --show ${terminus_package} | awk '{ print \$2 }')\"",
        before  => Package[$terminus_package],
      }

      package { $terminus_package:
        ensure   => $package_ensure,
        name     => $terminus_package,
        provider => 'dpkg',
        source   => $real_terminus_package_source,
        before   => [
          Package[$puppet_master_package],
        ],
        notify   => Service[$puppet_master_service],
      }
    }

    if $common_package_source != undef {
      $puppet_master_common_package = "${puppet_master_package}-common"
      $real_common_package_source   = '/tmp/puppetmaster-common.deb'

      wget::fetch { $puppet_master_common_package:
        source      => $common_package_source,
        destination => $real_common_package_source,
        before      => Package[$puppet_master_common_package],
      }

      # remove any version previously installed with apt
      exec { "remove apt ${puppet_master_common_package}":
        command => "dpkg -r ${puppet_master_common_package}",
        onlyif  => "dpkg --list ${puppet_master_common_package} | grep '^i' && apt-cache madison ${puppet_master_common_package} | grep \"\$(dpkg-query --show ${puppet_master_common_package} | awk '{ print \$2 }')\"",
        before  => Package[$puppet_master_common_package],
      }

      package { $puppet_master_common_package:
        ensure   => $package_ensure,
        provider => 'dpkg',
        source   => $real_common_package_source,
        before   => Package[$puppet_master_package],
        notify   => Service[$puppet_master_service],
      }
    }

    $real_package_source = '/tmp/puppetmaster.deb'

    wget::fetch { $puppet_master_package:
      source      => $package_source,
      destination => $real_package_source,
      before      => Package[$puppet_master_package],
    }

    # remove any version previously installed with apt
    exec { "remove apt ${puppet_master_package}":
      command => "dpkg -r ${puppet_master_package}",
      onlyif  => "dpkg --list ${puppet_master_package} | grep '^i' && apt-cache madison ${puppet_master_package} | grep \"\$(dpkg-query --show ${puppet_master_package} | awk '{ print \$2 }')\"",
      before  => Package[$puppet_master_package],
    }

    package { $puppet_master_package:
      ensure   => $package_ensure,
      provider => 'dpkg',
      source   => $real_package_source,
      notify   => Service[$puppet_master_service],
    }
  } elsif $::osfamily == 'Debian' {
    file { $puppet::params::puppetmaster_defaults:
      mode    => '0644',
      owner   => 'root',
      group   => 'root',
      before  => Package[$puppet_master_package],
      content => template("puppet/${puppet::params::puppetmaster_defaults}.erb"),
    }
    file { $puppet::params::puppetqd_defaults:
      mode    => '0644',
      owner   => 'root',
      group   => 'root',
      before  => Package['puppetmaster-common'],
      content => template("puppet/${puppet::params::puppetqd_defaults}.erb"),
    }
    package { 'puppetmaster-common':
      ensure => $version,
    }
    package { $puppet_master_package:
      ensure  => $version,
      require => Package[puppetmaster-common],
    }
  } else {
    package { $puppet_master_package:
      ensure => $version,
    }
  }

  Anchor['puppet::master::begin'] ->
  class {'puppet::passenger':
    puppet_passenger_port    => $puppet_passenger_port,
    puppet_docroot           => $puppet_docroot,
    puppet_root              => $puppet_root,
    apache_serveradmin       => $apache_serveradmin,
    puppet_conf              => $::puppet::params::puppet_conf,
    puppet_ssldir            => $puppet_ssldir,
    certname                 => $certname,
    dns_alt_names            => $dns_alt_names ? { undef => undef, default => join( $dns_alt_names,"," ) },
    generate_ssl_certs       => $generate_ssl_certs,
    puppet_passenger_tempdir => $puppet_passenger_tempdir,
    ca_server                => $ca_server,
    ca_port                  => $ca_port,
  } ->
  Anchor['puppet::master::end']

  service { $puppet_master_service:
    ensure  => stopped,
    enable  => false,
    require => File[$::puppet::params::puppet_conf],
  }

  if ! defined(File[$::puppet::params::puppet_conf]){
    file { $::puppet::params::puppet_conf:
      ensure  => 'file',
      mode    => '0644',
      require => File[$::puppet::params::confdir],
      owner   => $::puppet::params::puppet_user,
      group   => $::puppet::params::puppet_group,
      notify  => $apache::manage_service_autorestart,
    }
  } else {
    File<| title == $::puppet::params::puppet_conf |> {
      notify  => $apache::manage_service_autorestart,
    }
  }

  if ! defined(File[$::puppet::params::confdir]) {
    file { $::puppet::params::confdir:
      ensure  => directory,
      mode    => '0755',
      require => Package[$puppet_master_package],
      owner   => $::puppet::params::puppet_user,
      group   => $::puppet::params::puppet_group,
      notify  => $apache::manage_service_autorestart,
    }
  } else {
    File<| title == $::puppet::params::confdir |> {
      notify  +> $apache::manage_service_autorestart,
      require +> Package[$puppet_master_package],
    }
  }

  file { $puppet_vardir:
    ensure       => directory,
    owner        => $::puppet::params::puppet_user,
    group        => $::puppet::params::puppet_group,
    notify       => $apache::manage_service_autorestart,
    require      => Package[$puppet_master_package]
  }

  Ini_setting {
    path    => $::puppet::params::puppet_conf,
    require => File[$::puppet::params::puppet_conf],
    notify  => $apache::manage_service_autorestart,
    section => 'master',
  }

  if $storeconfigs {
    if $manage_puppetdb {
      Anchor['puppet::master::begin'] ->
      class { 'puppet::storeconfigs':
        dbserver                   => $storeconfigs_dbserver,
        dbport                     => $storeconfigs_dbport,
        puppet_service             => $apache::manage_service_autorestart,
        puppet_conf                => $::puppet::params::puppet_conf,
        puppet_master_package      => $puppet_master_package,
        puppetdb_startup_timeout   => $puppetdb_startup_timeout,
        puppetdb_strict_validation => $puppetdb_strict_validation,
        puppetdb_version           => $puppetdb_version,
      } ->
      Anchor['puppet::master::end']
    } else {
      ini_setting {'puppetmasterstoreconfigs':
        ensure  => $storeconfigs ? { undef => absent, default => present },
        setting => 'storeconfigs',
        value   => $storeconfigs,
      }
    }
  }

  if $environments == 'directory' {
    ini_setting {'puppetmastermodulepath':
      ensure  => absent,
      setting => 'modulepath',
      value   => $modulepath,
    }

    ini_setting {'puppetmastermanifest':
      ensure  => absent,
      setting => 'manifest',
      value   => $manifest,
    }

    ini_setting {'puppetmasterenvironmentpath':
      ensure  => $environmentpath ? { undef => absent, default => present },
      setting => 'environmentpath',
      value   => $environmentpath,
    }
  } elsif $environments == 'config' {
    $ensure_modulepath = $modulepath ? {
      undef                         => absent,
      $::puppet::params::modulepath => absent,
      '$confdir/modules'            => absent,
      default                       => present,
    }

    if $external_nodes != undef {
      ini_setting {'puppetmasterencconfig':
        ensure  => present,
        setting => 'external_nodes',
        value   => $external_nodes,
      }

      ini_setting {'puppetmasternodeterminus':
        ensure  => present,
        setting => 'node_terminus',
        value   => 'exec'
      }
    } elsif $node_terminus != undef {
      ini_setting {'puppetmasternodeterminus':
        ensure  => present,
        setting => 'node_terminus',
        value   => $node_terminus
      }
    }
  }

  ini_setting {'puppetmasterhieraconfig':
    ensure  => $hiera_config ? {
      undef                           => absent,
      $::puppet::params::hiera_config => absent,
      '$confdir/hiera.yaml'           => absent,
      default                         => present,
    },
    setting => 'hiera_config',
    value   => $hiera_config,
  }

  ini_setting {'puppetmasterautosign':
    ensure  => $autosign ? { undef => absent, default => present },
    setting => 'autosign',
    value   => "${autosign}",
  }

  ini_setting {'puppetmasterca':
    ensure  => $ca_server ? { undef => absent, default => present },
    setting => 'ca',
    value   => 'false',
  }

  ini_setting {'puppetmastercertname':
    ensure  => $certname ? { undef => absent, default => present },
    setting => 'certname',
    value   => $certname,
  }

  ini_setting {'puppetmasterreports':
    ensure  => $reports ? { undef => absent, default => present },
    setting => 'reports',
    value   => $reports,
  }

  ini_setting {'puppetmasterpluginsync':
    ensure  => $pluginsync ? { undef => absent, true => absent, default => present },
    setting => 'pluginsync',
    value   => $pluginsync,
  }

  ini_setting {'puppetmasterparser':
    ensure  => $parser ? { undef => absent, 'current' => absent, default => present },
    setting => 'parser',
    value   => $parser,
  }

  ini_setting {'puppetmasterreport':
    ensure  => $reporturl ? { undef => absent, default => present },
    setting => 'reporturl',
    value   => $reporturl,
  }

  ini_setting {'puppetmasterdnsaltnames':
    ensure  => $dns_alt_names ? { undef => absent, default => present },
    setting => 'dns_alt_names',
    value   => $dns_alt_names ? { undef => undef, default => join($dns_alt_names, ",") },
  }

  ini_setting {'puppetmasterdigestalgorithm':
    ensure  => $digest_algorithm ? { undef => absent, 'md5' => absent, default => present },
    setting => 'digest_algorithm',
    value   => $digest_algorithm,
  }

  if $strict_variables != undef {
    validate_bool(str2bool($strict_variables))
    ini_setting {'puppetmasterstrictvariables':
      ensure  => present,
      setting => 'strict_variables',
      value   => $strict_variables,
    }
  }

  anchor { 'puppet::master::end': }
}
