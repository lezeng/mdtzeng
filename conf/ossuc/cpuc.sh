#!/bin/sh

path=$(pwd)

cp -rf ../clientResouce/Resource /var/www/html/uc/
cp -rf ./center/*.xml /var/www/html/uc/
cp -rf ./1.04 /var/www/html/uc/
rm -rf /var/www/html/uc/1.04/*txt
rm -rf /var/www/html/uc/1.04/script

echo ""
echo finished!
