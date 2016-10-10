#! /usr/bin/env bash

echo "Creating /data..."

if [ ! -d "/data" ]; then
  mkdir /data
fi

echo "Installing git..."

yum install -y git

echo "Clone shell.git..."

cd /data && git clone https://github.com/bkbabydp/shell.git

echo "done."
