#!/bin/bash

#script that updates cloudflare domains
#requires jshon, https://github.com/keenerd/jshon

ipsites[0]="myip.dnsdynamic.org"
ipsites[1]="ifconfig.me"
ipsites[2]="icanhazip.com"
ipsites[3]="ipecho.net/plain"

#put hosts here
hosts[0]=""

#put info here
email=""
api_key=""

validIp="\b(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b"

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
		echo "Could not get IP!"
		exit
	fi
}

isNewAddress()
{
	#if it's matching, remove the corresponding ip index number
	for (( i = 0; i < "${#subhost_ip[@]}"; i++ )); do
		if [[ "$public" == "${subhost_ip[$i]}" ]]; then
			unset subhost_ip_index["$i"]
		fi
	done

	#rebuild array to strip out null fields
	subhost_ip_index=( "${subhost_ip_index[@]}" )
}

getStoredIP()
{
	curl -s https://www.cloudflare.com/api_json.html \
	-d 'a=rec_load_all' \
	-d "tkn=$api_key" \
	-d "email=$email" \
	-d "z=$host" > ./rec_load_all.json 2>&1

	subhost_type=( $( jshon -F ./rec_load_all.json -e response -e recs -e objs -a -e type | sed 's|"||g' | egrep -o "[[:upper:]]+" ) )

	unset subhost_ip
	unset subhost_ip_index
	for (( i = 0; i < "${#subhost_type[@]}"; i++ )); do
		if [[ "${subhost_type[$i]}" == "A" ]]; then
			#save A record ip addresses
			subhost_ip=( "${subhost_ip[@]}" "$( jshon -F ./rec_load_all.json -e response -e recs -e objs -e $i -e content | sed 's|"||g' | egrep -o "$validIp" )" )
			#save index of A records
			subhost_ip_index=( "${subhost_ip_index[@]}" "$i" )
		fi
	done
}

updateCloudflare()
{
	if [[ ${#subhost_ip_index[@]} -ne 0 ]]; then
		for object in "${subhost_ip_index[@]}"; do

			#grab current settings for some fields as to not overwrite
			ttl="$( jshon -F ./rec_load_all.json -e response -e recs -e objs -e $object -e ttl | sed 's|"||g' | egrep -o "[[:digit:]]+" )"
			name="$( jshon -F ./rec_load_all.json -e response -e recs -e objs -e $object -e name | sed 's|"||g' )"
			service_mode="$( jshon -F ./rec_load_all.json -e response -e recs -e objs -e $object -e service_mode | sed 's|"||g' | egrep -o "[0-1]" )"

			#grab host id
			host_id="$( jshon -F ./rec_load_all.json -e response -e recs -e objs -e $object -e rec_id | sed 's|"||g' | egrep -o "[[:digit:]]+" )"

			#update record using cloudflare api
			curl -s https://www.cloudflare.com/api_json.html \
				-d "a=rec_edit" \
				-d "tkn=$api_key" \
				-d "email=$email" \
				-d "z=$host" \
				-d "type=A" \
				-d "ttl=$ttl" \
				-d "name=$name" \
				-d "service_mode=$service_mode" \
				-d "id=$host_id" \
				-d "content=$public" > ./rec_edit.json 2>&1

			#parse json for response
			status="$( jshon -F ./rec_edit.json -e result | sed 's|"||g' )"
			new_ip="$( jshon -Q -F ./rec_edit.json -e response -e rec -e obj -e content | sed 's|"||g' )"

			#show response
			if [[ "$status" == "success" ]]; then
				if [[ "$new_ip" != "$public" ]]; then
					echo "Error: IP address not updated correctly for $host $host_id!"
					echo "Current:  $public"
					echo "Response: $new_ip"
				else
					echo "Successfully updated DNS for $name $host_id."
				fi
			elif [[ "$status" == "nochg" ]]; then
				echo "Updated DNS for $host, but there was no change!"
			elif [[ "$status" == "error" ]]; then
				echo "Error!"
				jshon -F ./rec_edit.json -e msg | sed 's|"||g'
			else
				echo "Unknown server response: $status"
				jshon -Q -F ./rec_edit.json -e msg | sed 's|"||g'
			fi
		done
	fi
}

getPublic

for host in "${hosts[@]}"; do
	getStoredIP
	isNewAddress
	updateCloudflare
done

rm -f ./rec_edit.json ./rec_load_all.json