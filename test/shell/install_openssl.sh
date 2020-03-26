set -eux

if [ ${#} -lt 1 ]; then
  echo "OpenSSL version required." 1>&2
  exit 1
fi

VERSION="${1}"

wget -q --no-check-certificate https://www.openssl.org/source/openssl-${VERSION}.tar.gz
tar xzf openssl-${VERSION}.tar.gz

pushd "openssl-${VERSION}"
./Configure --prefix=/usr "linux-$(uname -m)"
make -s -j$(nproc)
sudo make -s install_sw
popd
