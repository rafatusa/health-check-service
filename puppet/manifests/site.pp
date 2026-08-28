# Masterless Puppet manifest for the Health Check Service.
#
# Applied by the pipeline's configure stage with:
#   sudo -E puppet apply /tmp/puppet/manifests/site.pp --detailed-exitcodes
#
# Inputs arrive as Facter environment facts (FACTER_app_image, FACTER_ghcr_user,
# FACTER_ghcr_token) so no secret is ever written into a manifest file on disk
# or interpolated into a command line.
#
# Responsibilities:
#   1. Install Docker and nginx.
#   2. Authenticate to GHCR and run the SHA-tagged application image.
#   3. Front the container with nginx on port 80.
#
# Every exec is guarded (onlyif/unless) so re-running the manifest is a no-op,
# which is what makes recovery re-runs free.

$app_image = $facts['app_image']
$ghcr_user = $facts['ghcr_user']
$container = 'health-check-service'
$app_port  = 8080

# Fail fast and loudly rather than silently deploying an empty image ref.
unless $app_image and $app_image != '' {
  fail('FACTER_app_image must be set to the fully qualified image reference')
}

Exec {
  path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
  timeout => 600,
}

# --- packages -------------------------------------------------------------

# Refresh the archive index. The cloud image's prebuilt index is old enough to
# name superseded package versions, which produces 404s on install.
exec { 'apt-update':
  command => 'apt-get update -y',
  tries   => 5,
  try_sleep => 15,
}

package { ['docker.io', 'nginx']:
  ensure  => installed,
  require => Exec['apt-update'],
}

service { 'docker':
  ensure  => running,
  enable  => true,
  require => Package['docker.io'],
}

# --- application container ------------------------------------------------

# The token is read from the inherited FACTER_ghcr_token environment variable
# INSIDE the shell, so it never appears in the command string, the process
# table, or the Puppet log.
exec { 'ghcr-login':
  command   => "printf '%s' \"\$FACTER_ghcr_token\" | docker login ghcr.io -u '${ghcr_user}' --password-stdin",
  provider  => shell,
  require   => Service['docker'],
  logoutput => false,
  unless    => 'test -f /root/.docker/config.json',
}

exec { 'pull-app-image':
  command => "docker pull '${app_image}'",
  require => Exec['ghcr-login'],
  unless  => "docker image inspect '${app_image}'",
}

# Remove the previous container only when it is not already running this exact
# image, so an unchanged apply causes no downtime.
exec { 'stop-old-container':
  command  => "docker rm -f '${container}'",
  provider => shell,
  onlyif   => "docker ps -a --filter name=^/${container}$ --format '{{.Names}}' | grep -q '^${container}$'",
  unless   => "test \"\$(docker inspect -f '{{.Config.Image}}' '${container}' 2>/dev/null)\" = '${app_image}' && test \"\$(docker inspect -f '{{.State.Running}}' '${container}' 2>/dev/null)\" = 'true'",
  require  => Exec['pull-app-image'],
}

exec { 'run-app-container':
  command  => "docker run -d --name '${container}' --restart always -p 127.0.0.1:${app_port}:${app_port} -e APP_COMMIT='${app_image}' '${app_image}'",
  provider => shell,
  unless   => "docker ps --filter name=^/${container}$ --filter status=running --format '{{.Names}}' | grep -q '^${container}$'",
  require  => Exec['stop-old-container'],
}

# --- nginx reverse proxy --------------------------------------------------

# The packaged default site answers on the public IP and would shadow ours.
file { '/etc/nginx/sites-enabled/default':
  ensure  => absent,
  require => Package['nginx'],
}

# NOTE: the heredoc tag is UNQUOTED (@(NGINX)) which disables interpolation
# entirely, so nginx's $host / $remote_addr survive verbatim. A quoted tag
# would make Puppet try to evaluate them and fail with "Unknown variable".
# The port is therefore substituted with inline_template rather than $-syntax.
file { '/etc/nginx/sites-available/health-check-service':
  ensure  => file,
  owner   => 'root',
  group   => 'root',
  mode    => '0644',
  content => @(NGINX),
    server {
        listen 80 default_server;
        server_name _;

        location / {
            proxy_pass http://127.0.0.1:8080;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_connect_timeout 5s;
            proxy_read_timeout 30s;
        }
    }
    | NGINX
  require => Package['nginx'],
}

file { '/etc/nginx/sites-enabled/health-check-service':
  ensure  => link,
  target  => '/etc/nginx/sites-available/health-check-service',
  require => File['/etc/nginx/sites-available/health-check-service'],
}

# Validate the configuration before reloading: a bad config must fail the
# apply, not take the running proxy down.
exec { 'nginx-config-test':
  command     => 'nginx -t',
  refreshonly => true,
  subscribe   => [
    File['/etc/nginx/sites-enabled/health-check-service'],
    File['/etc/nginx/sites-enabled/default'],
  ],
  notify      => Service['nginx'],
}

service { 'nginx':
  ensure  => running,
  enable  => true,
  require => [
    File['/etc/nginx/sites-enabled/health-check-service'],
    Exec['run-app-container'],
  ],
}
