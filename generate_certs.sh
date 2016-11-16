#!/bin/bash

set -e

ip=$1
if [[ "${ip}X" == "X" ]]; then
  echo "USAGE: ./director_certs.sh <public IP>"
  exit 1
fi

echo "Generating certs for ${ip}"

certs=`dirname $0`/certs/${ip}

rm -rf $certs && mkdir -p $certs

cd $certs

echo "Generating CA..."
openssl genrsa -out rootCA.key 2048
yes "" | openssl req -x509 -new -nodes -key rootCA.key \
  -out rootCA.pem -days 99999

function generateCert {
  name=$1
  ip=$2

  cat >openssl-exts.conf <<-EOL
extensions = san
[san]
subjectAltName = IP:${ip}
EOL

  echo "Generating private key..."
  openssl genrsa -out ${name}.key 2048

  echo "Generating certificate signing request for ${ip}..."
  # golang requires to have SAN for the IP
  openssl req -new -nodes -key ${name}.key \
    -out ${name}.csr \
    -subj "/C=US/O=BOSH/CN=${ip}"

  echo "Generating certificate ${ip}..."
  openssl x509 -req -in ${name}.csr \
    -CA rootCA.pem -CAkey rootCA.key -CAcreateserial \
    -out ${name}.crt -days 99999 \
    -extfile ./openssl-exts.conf

  echo "Deleting certificate signing request and config..."
  rm ${name}.csr
  rm ./openssl-exts.conf
}

generateCert director ${ip}

echo "Generating yaml file for golang CLI substitution..."
certs=`dirname $0`/certs/${ip}

function indent() {
  c='s/^/  /'
  case $(uname) in
    Darwin) sed -l "$c";;
    *)      sed -u "$c";;
  esac
}


cat > certs-${ip}.yml <<EOF
---
director_ssl_key: |
$(cat director.key | indent)

director_ssl_cert: |
$(cat director.crt | indent)

director_ca_cert: |
$(cat rootCA.pem | indent)
EOF

echo "Combine manifest template below with your BOSH manifest:"
cat certs-${ip}.yml
echo
