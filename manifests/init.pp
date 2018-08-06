# rhsm
#
# Subscribe the node to RHSM
#
# Copyright 2014 Ger Apeldoorn, unless otherwise noted.
#
# @summary Subscribe the node to RHSM
#
# @param rh_user [String] User for the Customer Portal.
#   You need to specify either (rh_user and rh_password) or (org and activationkey)
# @param rh_password [String] Password for the rh_user account
# @param org [String] Organization to use
# @param activationkey [String] Activationkey to use
# @param servername [String] Servername, default provided
#   Used directly in rhsm.conf template
# @param serverprefix [String] server.prefix to use
#   Used directly in rhsm.conf template
#   /rhsm for Satellite 6
#   /subscription for RHSM
# @param serverport [Integer] server.port to use
#   Used directly in rhsm.conf template
# @param ca_cert_dir [String] Server CA certificate location
# @param repo_ca_cert_filename [String] File containting the CA cert to use when generating yum repo configs
#   katello-server-ca.pem for Satellite 6
#   redhat-uep.pem for RHSM
# @param repo_ca_cert_source [String] URI, if set the content is used for CA file resource ${ca_cert_dir}/${repo_ca_cert_filename}
#   Possible values are puppet:, file: and http:
# @param manage_repos [Integer] 1 if subscription manager should manage yum repos file or
#   0 if the subscription is only used for tracking purposes
# @param full_refresh_on_yum [Integer] rhsm.full_refresh_on_yum
#   Used directly in rhsm.conf template
#   1 for Satellite 6
#   0 for RHSM
# @param pool [String] Attach system to a specific pool instead of auto attach to compatible subscriptions
# @param proxy_hostname [String] Proxy hostname
# @param proxy_port [Integer] Proxy port
# @param proxy_user [String] Proxy user
# @param proxy_password [String] Proxy password
# @param baseurl [String] Base URL for rhsm, default provided
# @param repo_extras [Boolean] Enable extras repository
# @param repo_optional [Boolean] Enable optional repository
#
# @example
#   include rhsm
#
# @example
#   # Hierafile:
#   ---
#   rhsm::rh_user: myuser
#   rhsm::rh_password: mypassword
#
# @author Ger Apeldoorn <info@gerapeldoorn.nl>
#
class rhsm (
  $rh_user               = undef,
  $rh_password           = undef,
  $org                   = undef,
  $activationkey         = undef,
  $pool                  = undef,
  $proxy_hostname        = undef,
  $proxy_port            = undef,
  $proxy_user            = undef,
  $proxy_password        = undef,
  $baseurl               = 'https://cdn.redhat.com',
  $servername            = 'subscription.rhsm.redhat.com',
  $serverprefix          = '/subscription',
  $serverport            = 443,
  $ca_cert_dir           = '/etc/rhsm/ca/',
  $repo_ca_cert_filename = 'redhat-uep.pem',
  $repo_ca_cert_source   = undef,
  $manage_repos          = 1,
  $full_refresh_on_yum   = 0,
  $rhel_release          = undef,
  $repo_els              = false,
  $repo_els_tools        = false,
  $repo_extras           = false,
  $repo_optional         = false,
  $repo_tools            = false,
  $satellite_version     = 6.3
) {

  if ($rh_user == undef and $rh_password == undef) and ($org == undef and $activationkey == undef) {
    fail("${module_name}: Must provide rh_user and rh_password or org and activationkey")
  }

  if $rh_user {
    $_user = " --username='${rh_user}'"
  } else {
    $_user = ''
  }

  if $rh_password {
    $_password = " --password='${rh_password}'"
  } else {
    $_password = ''
  }

  if $org {
    $_org = " --org='${org}'"
  } else {
    $_org = ''
  }

  if $activationkey {
    $_activationkey = " --activationkey='${activationkey}'"
  } else {
    $_activationkey = ''
  }

  if $proxy_hostname {
    if $proxy_user and $proxy_password {
      $proxycli = " --proxy=http://${proxy_hostname}:${proxy_port} --proxyuser=${proxy_user} --proxypass=${proxy_password}"
    } else {
      $proxycli = " --proxy=http://${proxy_hostname}:${proxy_port}"
    }
  } else {
    $proxycli = ''
  }

  if $rhel_release {
    $rhel_release_opt = " --release=${rhel_release}"
  }else {
    $rhel_release_opt = ''
  }

  if $pool == undef {
    $command = "subscription-manager attach --auto${proxycli}"
  }

  exec {'sm yum clean all':
    command     => '/usr/bin/yum clean all',
    refreshonly => true,
    subscribe   => Package['subscription-manager'],
  }

  file { '/etc/rhsm/rhsm.conf':
    ensure  => file,
    content => template('rhsm/rhsm.conf.erb'),
  }

  if $repo_ca_cert_source {
    file { "${ca_cert_dir}/${repo_ca_cert_filename}":
      ensure => present,
      mode   => '0644',
      source => $repo_ca_cert_source,
    }
  }

  exec { 'RHSM-register':
    command   => "subscription-manager register --name='${::fqdn}'${_user}${_password}${_org}${_activationkey}${rhel_release_opt}${proxycli}",
    onlyif    => 'subscription-manager identity 2>&1 | grep "not yet registered"',
    path      => '/bin:/usr/bin:/usr/sbin',
    logoutput => true,
    require   => Package['subscription-manager'],
  }

  exec { 'RHSM-subscribe':
    command   => $command,
    onlyif    => 'subscription-manager list 2>&1 | grep "Expired\|Not Subscribed\|Unknown"',
    path      => '/bin:/usr/bin:/usr/sbin',
    logoutput => true,
    require   => Exec['RHSM-register'],
  }

  if $pool {
    exec { 'RHSM-attach-pool':
      command   => "subscription-manager attach --pool=${pool}${proxycli}",
      unless    => "subscription-manager list --consumed | grep ${pool}",
      path      => '/bin:/usr/bin:/usr/sbin',
      logoutput => true,
      require   => Exec['RHSM-register'],
    }
  }

  if $repo_extras {
    ::rhsm::repo { "rhel-${::operatingsystemmajrelease}-server-extras-rpms":
      require => Exec['RHSM-register'],
    }
  }

  if $repo_optional {
    ::rhsm::repo { "rhel-${::operatingsystemmajrelease}-server-optional-rpms":
      require => Exec['RHSM-register'],
    }
  }

  if $repo_tools {
    exec { 'RHSM-REPO-TOOLS':
      command   => "subscription-manager repos --enable=rhel-${::operatingsystemmajrelease}-server-satellite-tools-${satellite_version}-rpms",
      onlyif    => 'yum repolist disabled | grep server-satellite-tools',
      path      => '/bin:/usr/bin:/usr/sbin',
      logoutput => true,
      require   => Exec['RHSM-register'],
    }
  }

  if $repo_els {
    exec { 'RHSM-REPO-ELS':
      command => "subscription-manager repos --enable=rhel-${::operatingsystemmajrelease}-server-els-rpms",
      onlyif  => 'yum repolist disabled | grep server-els-rpms',
      path    => '/bin:/usr/bin:/usr/sbin',
      require => Exec['RHSM-register'],
    }
  }

  if $repo_els_tools {
    exec { 'RHSM-ELS-TOOLS':
      command => "subscription-manager repos --enable=rhel-${::operatingsystemmajrelease}-server-els-satellite-tools-${satellite_version}-rpms",
      onlyif  => 'yum repolist disabled | grep server-els-satellite-tools',
      path    => '/bin:/usr/bin:/usr/sbin',
      require => Exec['RHSM-register'],
    }
  }

}
