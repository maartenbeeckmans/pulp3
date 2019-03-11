#
#
#
class profile_pulp3 (
  Stdlib::Absolutepath $media_root = '/var/lib/pulp',
  Optional[String]     $secret_key = undef,
  String               $pulp_db_username = 'pulp',
  String               $pulp_db_password = 'pulp',
  String               $pulp_db_database = 'pulp',
) {

  # Generate the secret key if not passed
  if ! $secret_key {
    $_secret_key = fqdn_rand_string('50','abcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*(-_=+)')
  } else {
    $_secret_key = $secret_key
  }

  include ::redis

  # Database
  class { '::postgresql::globals':
    encoding            => 'UTF-8',
    manage_package_repo => true,
    version             => '10',
  }

  -> class { '::postgresql::server':
    ip_mask_allow_all_users => '0.0.0.0/32',
    listen_addresses        => 'localhost',
  }

  class { '::postgresql::client': }

  postgresql::server::db { $pulp_db_database:
    user     => $pulp_db_username,
    password => $pulp_db_password,
    grant    => 'all',
    before   => Exec['bootstrap::pulp3'],
  }

  postgresql::server::pg_hba_rule { $pulp_db_database:
    type        => 'local',
    database    => $pulp_db_database,
    user        => $pulp_db_username,
    auth_method => 'md5',
    before      => Exec['bootstrap::pulp3'],
  }

  # packages for building atm
  $packages = [
    'python36',
    'git',
    'tig',
    'gcc',
    'make',
    'cmake',
    'bzip2-devel',
    'expat-devel',
    'file-devel',
    'glib2-devel',
    'libcurl-devel',
    'libxml2-devel',
    'python36-devel',
    'rpm-devel',
    'openssl-devel',
    'sqlite-devel',
    'xz-devel',
    'zchunk-devel',
    'zlib-devel',
  ]

  package { $packages:
    ensure => present,
  }

  # systemd files for dev
  $systemd_files = [
    'pulp-resource-manager.service',
    'pulp-rpm-gunicorn.service',
    'pulp-server.service',
    'pulp-worker@.service',
  ]

  $systemd_files.each | $systemd_file | {
    systemd::unit_file { $systemd_file:
      source => "puppet:///modules/${module_name}/systemd/${systemd_file}",
      before => Exec['bootstrap::pulp3'],
    }
  }

  file { '/etc/pulp':
    ensure => directory,
  }

  $settings_hash = {
    'media_root'       => $media_root,
    'secret_key'       => $_secret_key,
    'pulp_db_database' => $pulp_db_database,
    'pulp_db_username' => $pulp_db_username,
    'pulp_db_password' => $pulp_db_password,
  }

  file { '/etc/pulp/settings.py':
    ensure  => present,
    content => epp('profile_pulp3/settings', $settings_hash)
  }

  file { '/opt/pulp':
    ensure => directory,
  }

  file { '/usr/bin/pcurl':
    ensure => present,
    mode   => '0755',
    source => "puppet:///modules/${module_name}/bin/pcurl",
  }

  file { '/usr/bin/bootstrap_pulp3':
    ensure => present,
    mode   => '0755',
    source => "puppet:///modules/${module_name}/bin/bootstrap",
  }

  exec { 'bootstrap::pulp3':
    path    => $::path,
    command => '/usr/bin/bootstrap_pulp3',
    creates => '/opt/pulp/pulpvenv/bin/activate',
    require => [
      Package[$packages],
      File['/opt/pulp'],
      File['/etc/pulp/settings.py'],
      File['/usr/bin/bootstrap_pulp3'],
      Service['redis'],
    ],
  }

}