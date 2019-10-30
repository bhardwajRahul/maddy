#!/bin/sh

if [ "$GOVERSION" == "" ]; then
    GOVERSION=1.13.0
fi
if [ "$MADDYVERSION" == "" ]; then
    MADDYVERSION=master
fi
if [ "$PREFIX" == "" ]; then
    PREFIX=/usr/local
fi
SYSTEMDUNITS=$PREFIX/lib/systemd
if [ "$CONFPATH" == "" ]; then
    CONFPATH=/etc/maddy/maddy.conf
fi

set -euo pipefail
IFS=$'\n'

mkdir -p maddy-setup/
cd maddy-setup/

if ! which go >/dev/null; then
    download=1
else
    SYSGOVERSION=`go version | grep -Po "([0-9]+\.){2}[0-9]+"`
    SYSGOMAJOR=`cut -f1 -d. <<<$SYSGOVERSION`
    SYSGOMINOR=`cut -f2 -d. <<<$SYSGOVERSION`
    SYSGOPATCH=`cut -f3 -d. <<<$SYSGOVERSION`
    WANTEDGOMAJOR=`cut -f1 -d. <<<$GOVERSION`
    WANTEDGOMINOR=`cut -f2 -d. <<<$GOVERSION`
    WANTEDGOPATCH=`cut -f3 -d. <<<$GOVERSION`

    downloadgo=0
    if [ $SYSGOMAJOR -ne $WANTEDGOMAJOR ]; then
        downloadgo=1
    fi
    if [ $SYSGOMINOR -lt $WANTEDGOMINOR ]; then
        downloadgo=1
    fi
    if [ $SYSGOPATCH -lt $WANTEDGOPATCH ]; then
        downloadgo=1
    fi

    if [ $downloadgo -eq 0 ]; then
        echo "Using system Go toolchain ($SYSGOVERSION, `which go`)." >&2
    fi
fi

if [ $downloadgo -eq 1 ]; then
    echo "Downloading Go $GOVERSION toolchain..." >&2
    if ! [ -e go$GOVERSION ]; then
        if ! [ -e go$GOVERSION.linux-amd64.tar.gz ]; then
            wget -q 'https://dl.google.com/go/go1.13.3.linux-amd64.tar.gz'
        fi
        tar xf go$GOVERSION.linux-amd64.tar.gz
        mv go go$GOVERSION
    fi
    export GOROOT=$PWD/go$GOVERSION
    export PATH=go$GOVERSION/bin:$PATH
fi


export GOPATH="$PWD/gopath"
export GOBIN="$GOPATH/bin"

echo 'Downloading and compiling maddy...' >&2

export GO111MODULE=on
go get github.com/foxcpp/maddy/cmd/{maddy,maddyctl}@$MADDYVERSION

echo 'Installing maddy...' >&2

sudo mkdir -p "$PREFIX/bin"
sudo cp "$GOPATH/bin/maddy" "$GOPATH/bin/maddyctl" "$PREFIX/bin/"

echo 'Downloading and installing systemd unit files...' >&2

wget -q "https://raw.githubusercontent.com/foxcpp/maddy/$MADDYVERSION/dist/systemd/maddy.service" -O maddy.service
wget -q "https://raw.githubusercontent.com/foxcpp/maddy/$MADDYVERSION/dist/systemd/maddy@.service" -O maddy@.service

sed -Ei "s!/usr/bin!$PREFIX/bin!g" maddy.service maddy@.service

sudo mkdir -p "$SYSTEMDUNITS/system/"
sudo cp maddy.service maddy@.service "$SYSTEMDUNITS/system/"
sudo systemctl daemon-reload

echo 'Creating maddy user and group...' >&2

sudo useradd -UMr -s /sbin/nologin maddy || true

echo 'Using configuration path:' $CONFPATH
if ! [ -e "$CONFPATH" ]; then
    echo 'Downloading and installing default configuration...' >&2

    wget -q "https://raw.githubusercontent.com/foxcpp/maddy/$MADDYVERSION/maddy.conf" -O maddy.conf
    sudo mkdir -p /etc/maddy/

    host=`hostname`
    read -p "What's your domain, btw? [$host] > " DOMAIN
    if [ "$DOMAIN" = "" ]; then
        DOMAIN=$host
    fi
    echo 'Good, I will put that into configuration for you.' >&2

    sed -Ei "s/^\\$\\(primary_domain\) = .+$/$\(primary_domain\) = $DOMAIN/" maddy.conf
    sed -Ei "s/^\\$\\(hostname\) = .+$/$\(hostname\) = $DOMAIN/" maddy.conf

    sudo cp maddy.conf /etc/maddy/
else
    echo "Configuration already exists in /etc/maddy/maddy.conf, skipping defaults installation." >&2
fi

echo "Okay, almost ready." >&2
echo "It's up to you to figure out TLS certificates and DNS stuff, though." >&2
echo "Here is the tutorial to help you:" >&2
echo "https://github.com/foxcpp/maddy/wiki/Tutorial:-Setting-up-a-mail-server-with-maddy" >&2