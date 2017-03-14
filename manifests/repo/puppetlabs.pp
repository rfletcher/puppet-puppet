#"
# This module is used to setup the puppetlabs repos
# that can be used to install puppet.
#
class puppet::repo::puppetlabs() {

  if($::osfamily == 'Debian') {
    Apt::Source {
      location    => 'http://apt.puppetlabs.com',
      key         => {
        id      => '47B320EB4C7C375AA9DAE1A01054B7A24BD6EC30',
        content => template('puppet/pgp.key'),
      },
    }

    if $::lsbdistid == 'Ubuntu' and versioncmp( $::lsbdistrelease, '16.04' ) >= 0 {
      $main_repo = 'PC1'
    } else {
      $main_repo = 'main'
    }

    apt::source { 'puppetlabs':      repos => $main_repo }
    apt::source { 'puppetlabs-deps': repos => 'dependencies' }
  } elsif $::osfamily == 'Redhat' {
    if $::operatingsystem == 'Fedora' {
      $ostype='fedora'
      $prefix='f'
    } else {
      $ostype='el'
      $prefix=''
    }

    yumrepo { 'puppetlabs-deps':
      baseurl  => "http://yum.puppetlabs.com/${ostype}/${prefix}\$releasever/dependencies/\$basearch",
      descr    => 'Puppet Labs Dependencies $releasever - $basearch ',
      enabled  => '1',
      gpgcheck => '1',
      gpgkey   => 'http://yum.puppetlabs.com/RPM-GPG-KEY-puppetlabs',
    }

    yumrepo { 'puppetlabs':
      baseurl  => "http://yum.puppetlabs.com/${ostype}/${prefix}\$releasever/products/\$basearch",
      descr    => 'Puppet Labs Products $releasever - $basearch',
      enabled  => '1',
      gpgcheck => '1',
      gpgkey   => 'http://yum.puppetlabs.com/RPM-GPG-KEY-puppetlabs',
    }
  } else {
    fail("Unsupported osfamily ${::osfamily}")
  }
}
