#!/usr/bin/env bash
# Run as root or with sudo
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root or with sudo."
  exit 1
fi

# Make script exit if a simple command fails and
# Make script print commands being executed
set -e -x

# Ensure curl is installed
apt-get update && apt-get install curl -y

# Set URLs to the source directories
source_pcre=https://onboardcloud.dl.sourceforge.net/project/pcre/pcre/8.45/
source_zlib=https://zlib.net/
source_openssl=https://www.openssl.org/source/
source_nginx=https://nginx.org/download/

# Look up latest versions of each package
version_pcre=pcre-8.45
version_zlib=zlib-1.2.13
version_openssl=openssl-3.0.8
version_nginx=nginx-1.24.0

# Set OpenPGP keys used to sign downloads
opgp_pcre=45F68D54BBE23FB3039B46E59766E084FB0F43D8
opgp_zlib=5ED46A6721D365587791E2AA783FCD8E58BCAFBA
opgp_nginx=13C82A63B603576156E30A4EA0EA981B66B0D967
opgp_openssl1=8657ABB260F056B1E5190839D9C4D26D0E604491
opgp_openssl2=B7C1C14360F353A36862E4D5231C84CDDCC69C45
opgp_openssl3=C1F33DD8CE1D4CC613AF14DA9195C48241FBF7DD
opgp_openssl4=95A9908DDFA16830BE9FB9003D30A3A9FF1360DC
opgp_openssl5=7953AC1FBC3DC8B3B292393ED5E9E43F7DF9EE8C
opgp_openssl6=A21FAB74B0088AA361152586B8EF1A6BA9DA2D5C
opgp_openssl7=E5E52560DD91C556DDBDA5D02064C53641C25E5D


# Set where OpenSSL and NGINX will be built
bpath=$(pwd)/build
mkdir "$bpath"

# Ensure the required software to compile NGINX is installed
apt-get -y remove nginx 

apt-get -y install \
  binutils \
  build-essential \
  curl \
  dirmngr \
  git \
  libssl-dev

# Download the source files
curl -L "${source_pcre}${version_pcre}.tar.gz" -o "${bpath}/pcre.tar.gz"
curl -L "${source_zlib}${version_zlib}.tar.gz" -o "${bpath}/zlib.tar.gz"
curl -L "${source_openssl}${version_openssl}.tar.gz" -o "${bpath}/openssl.tar.gz"
curl -L "${source_nginx}${version_nginx}.tar.gz" -o "${bpath}/nginx.tar.gz"

# Download the signature files
curl -L "${source_pcre}${version_pcre}.tar.gz.sig" -o "${bpath}/pcre.tar.gz.sig"
curl -L "${source_zlib}${version_zlib}.tar.gz.asc" -o "${bpath}/zlib.tar.gz.asc"
curl -L "${source_openssl}${version_openssl}.tar.gz.asc" -o "${bpath}/openssl.tar.gz.asc"
curl -L "${source_nginx}${version_nginx}.tar.gz.asc" -o "${bpath}/nginx.tar.gz.asc"

# Verify the integrity and authenticity of the source files through their OpenPGP signature
cd "$bpath"
GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
gpg --keyserver keyserver.ubuntu.com --recv-keys "$opgp_pcre" "$opgp_zlib" "$opgp_nginx"
gpg --keyserver keyserver.ubuntu.com --recv-keys "$opgp_openssl1" "$opgp_openssl2" "$opgp_openssl3" "$opgp_openssl4" "$opgp_openssl5" "$opgp_openssl6" "$opgp_openssl7"
gpg --batch --verify pcre.tar.gz.sig pcre.tar.gz
gpg --batch --verify zlib.tar.gz.asc zlib.tar.gz
gpg --batch --verify openssl.tar.gz.asc openssl.tar.gz
gpg --batch --verify nginx.tar.gz.asc nginx.tar.gz

# Expand the source files
cd "$bpath"
for archive in ./*.tar.gz; do
  tar xzf "$archive"
done

# Clean up source files
rm -rf \
  "$GNUPGHOME" \
  "$bpath"/*.tar.*

# Download custom Nginx modules
git clone https://github.com/dvershinin/nginx-sticky-module-ng.git
git clone https://github.com/google/ngx_brotli.git
git clone https://github.com/yaoweibin/nginx_upstream_check_module.git

# Test to see if our version of gcc supports __SIZEOF_INT128__
if gcc -dM -E - </dev/null | grep -q __SIZEOF_INT128__
then
  ecflag="enable-ec_nistp_64_gcc_128"
else
  ecflag=""
fi

# Build NGINX, with various modules included/excluded
cd "$bpath/$version_nginx"

# Necessary patches
patch -p1 < "$bpath/nginx_upstream_check_module/check_1.20.1+.patch"

./configure \
  --prefix=/etc/nginx \
  --with-cc-opt="-O3 -fPIE -fstack-protector-strong -Wformat -Werror=format-security" \
  --with-ld-opt="-Wl,-Bsymbolic-functions -Wl,-z,relro" \
  --with-pcre="$bpath/$version_pcre" \
  --with-zlib="$bpath/$version_zlib" \
  --with-openssl-opt="no-weak-ssl-ciphers no-ssl3 no-shared $ecflag -DOPENSSL_NO_HEARTBEATS -fstack-protector-strong" \
  --with-openssl="$bpath/$version_openssl" \
  --add-module="$bpath/nginx-sticky-module-ng" \
  --add-module="$bpath/ngx_brotli" \
  --add-module="$bpath/nginx_upstream_check_module" \
  --sbin-path=/usr/sbin/nginx \
  --modules-path=/usr/lib/nginx/modules \
  --conf-path=/etc/nginx/nginx.conf \
  --error-log-path=/var/log/nginx/error.log \
  --http-log-path=/var/log/nginx/access.log \
  --pid-path=/var/run/nginx.pid \
  --lock-path=/var/run/nginx.lock \
  --http-client-body-temp-path=/var/cache/nginx/client_temp \
  --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
  --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
  --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
  --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
  --user=nginx \
  --group=nginx \
  --with-file-aio \
  --with-http_auth_request_module \
  --with-http_gunzip_module \
  --with-http_gzip_static_module \
  --with-http_mp4_module \
  --with-http_realip_module \
  --with-http_secure_link_module \
  --with-http_slice_module \
  --with-http_ssl_module \
  --with-http_stub_status_module \
  --with-http_sub_module \
  --with-http_v2_module \
  --with-pcre-jit \
  --with-stream \
  --with-stream_ssl_module \
  --with-threads \
  --without-http_empty_gif_module \
  --without-http_geo_module \
  --without-http_split_clients_module \
  --without-http_ssi_module \
  --without-mail_imap_module \
  --without-mail_pop3_module \
  --without-mail_smtp_module
make
make install
make clean
strip -s /usr/sbin/nginx*

# Create NGINX systemd service file if it does not already exist
if [ ! -e "/lib/systemd/system/nginx.service" ]; then
  # Control will enter here if the NGINX service doesn't exist.
  file="/lib/systemd/system/nginx.service"

  /bin/cat >$file <<'EOF'
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
fi
