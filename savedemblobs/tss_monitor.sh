#!/bin/bash

tssfile="./tss.md5"

getcurrentmd5()
{
	var="$( curl -A 'compilingEntropy' -s "http://api.ineal.me/tss/all/includebeta" | md5sum | sed "s| .*||g" )"
	if [[ -n "$var" ]]; then
		echo "$var"
	else
		echo "Communication error! Unable to get currently signed firmwares!"
		exit
	fi
}

getstoredmd5()
{
	var="$( egrep -o '(^[[:xdigit:]]{32}$)' "$tssfile" )"
	if [[ -n "$var" ]]; then
		echo "$var"
	else
		echo "File read error! Unable to get tss status from file!"
		exit
	fi
}

currentmd5="$( getcurrentmd5 )"

if [[ ! -e "$tssfile" ]]; then
	echo "$currentmd5" > "$tssfile"
fi

storedmd5="$( getstoredmd5 )"

if [[ "$currentmd5" != "$storedmd5" ]]; then
	#Checksums do not match
	echo "checksums do not match"
	echo "$currentmd5" > "$tssfile"
	echo "checking new firmwares..."
	~/savesh.sh
	echo "done."
else
	#Checksums do match
	echo "checksums match"
	exit
fi