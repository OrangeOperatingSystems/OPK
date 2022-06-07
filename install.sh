#!/bin/sh
install() {
  chmod +x ./opk.sh
  cp ./opk.sh /usr/bin/opk
  cp ./opk.conf /etc/opk.conf
  cd /usr/share
  git clone https://github.com/orangeoperatingsystems/our --depth 1 --jobs 5
  mkdir -p /usr/share/opk
  mv /usr/share/our/* /usr/share/opk/
  mv /usr/share/our/.* /usr/share/opk/
  rm -rf /usr/share/our
  touch /usr/share/opk/packages.sh
  echo '#!/bin/sh' > /usr/share/opk/packages.sh
  mkdir -p /usr/share/opk/removeinfo
}

install && exit

echo "\n \n \n Failed to install, you may have forgotten to run as root or you already have opk installed."

