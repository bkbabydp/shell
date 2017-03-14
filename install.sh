#! /usr/bin/env bash

declare basepath=$(cd `dirname "$0"`; pwd)
cd "$basepath"

declare root_name=data
declare app_name=shell

echo "Creating /$root_name..."

if [ ! -d "/$root_name" ]; then
  mkdir /$root_name
fi

echo "Installing git..."

yum install -y git

echo "Installing app..."

if [ ! -d "/$root_name/$app_name" ]; then
  cd /$root_name && git clone https://github.com/bkbabydp/shell.git
else
  cd /$root_name/$app_name && git pull origin master
fi

echo "done."
