#!/bin/bash

echo "Get keys for what device?"
read device

echo "Get keys for what version?"
read version

buildid="$( curl -s -A 'compilingEntropy' "http://api.ios.icj.me/v2/$device/$version/buildid" )"

curl -s "www.icj.me/ios/keys/$device/$buildid" | grep -A 2 "<td class=\"image\">" | sed -r 's#<([^>]|("[^"]"))*>##g' > "./keys.txt"

echo "What keys do you want?"
read keys

echo ""
grep -A 2 -i "$keys" "./keys.txt" | sed -r -e "s|^[[:xdigit:]]{32}$|iv: &|g" -e "s|^[[:xdigit:]]{64}$|key: &|g"
