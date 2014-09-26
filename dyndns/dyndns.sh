#!/bin/bash

#script that updates dnsdynamic.org domains

sites[0]="myip.dnsdynamic.org"
sites[1]="ifconfig.me"
sites[2]="icanhazip.com"
sites[3]="ipecho.net/plain"

#hosts to update go here
hosts[0]=""
hosts[1]=""

#user creds here
uname=""
passwd=""

validIp="\b(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b"

addressfile="/private/var/root/address.md5"

getPublic()
{
	#get public IP address from first site to respond
	for address in "${ipsites[@]}"; do
		public="$( curl --connect-timeout 5 -s "$address" | tr -d "\n\r" | egrep -o "$validIp" )"
		if [ $( echo -n "$public" | egrep -c "$validIp" ) -eq 1 ]; then
			break
		fi
	done
	if [ $( echo -n "$public" | egrep -c "$validIp" ) -ne 1 ]; then
		exit
	fi
}

isNewAddress()
{
	if [[ "$currentmd5" != "$storedmd5" ]]; then
		#Checksums do not match
		echo "checksums do not match"
		updatePublic
		exit
	else
		#Checksums do match
		echo "checksums match"
		exit
	fi
}

getstoredmd5()
{
	var="$( egrep -o '(^[[:xdigit:]]{32}$)' "$addressfile" )"
	if [[ -n "$var" ]]; then
		echo "$var"
	else
		echo "File read error! Unable to get address status from file!"
		exit
	fi
}

updatePublic()
{
	for host in "${hosts[@]}"; do
		status="$( curl -s -u $uname:$passwd "https://www.dnsdynamic.org/api/?hostname=$host&myip=$public" --cacert /usr/lib/ssl/certs/ca-certificates.crt )"
		if [[ "$status" == "good" ]]; then
			echo "Successfully updated DNS for $host."
			echo -n "$currentmd5" > "$addressfile"
		elif [[ "$status" == "nochg" ]]; then
			echo "Updated DNS for $host, but there was no change!"
			echo -n "$currentmd5" > "$addressfile"
		else
			echo "Unknown server response: $status"
		fi
	done
}

getPublic
currentmd5="$( echo -n "$public" | md5sum | sed "s| .*||g" )"

#first run?
if [[ ! -e "$addressfile" ]]; then
	echo "$currentmd5" > "$addressfile"
fi

storedmd5="$( getstoredmd5 )"

isNewAddress