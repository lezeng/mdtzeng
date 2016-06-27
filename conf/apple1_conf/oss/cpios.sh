#!/bin/sh

path=$(pwd)

cp -rf ../clientResouce/Resource /var/www/html/ios/
cp -rf ./center/*.xml /var/www/html/ios/
cp -rf ./1.04 /var/www/html/ios/
rm -rf /var/www/html/ios/1.04/*txt
rm -rf /var/www/html/ios/1.04/script

echo ""
echo finished!
