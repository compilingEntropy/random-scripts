#!/bin/bash

cd "$( dirname "${BASH_SOURCE[0]}" )"

date="$( date '+%F' )"
time="$( date '+%T' )"

is_down()
{
	server="$1"
	port="$2"

	nc -z -w 2 "$server" "$port" &> /dev/null
	echo "$?"
}

generate_report()
{
	server="$1"
	port="$2"
	state="$3"

	server_info="./$server:$port.info"
	report_tempfile="./$( cat /dev/urandom | tr -cd [:xdigit:] | head -c 11 )"

	save_report()
	{
		should_notify="1"
		echo "Server: $server"					>  "$report_tempfile"
		echo "Port: $port"						>> "$report_tempfile"
		echo "Current State: $state"			>> "$report_tempfile"
		echo "Down Since: $first_down"			>> "$report_tempfile"
		echo "Total Time Down: $total_downtime"	>> "$report_tempfile"
		echo "Report Time: $date $time"			>> "$report_tempfile"
	}

	#calculate total_downtime based off of first_down
	downtime_calc()
	{
		secs=$(( $( date -d "$date $time" '+%s' ) - $( date -d "$first_down" '+%s' ) ))

		d=$(( secs / 86400 ))
		h=$(( ( secs / 3600 ) % 24 ))
		m=$(( ( secs / 60 ) % 60 ))
		s=$(( secs % 60 ))

		echo "$d"'d' "$h"'h' "$m"'m' "$s"'s'
	}

	should_notify="0"
	date_regex="[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}"
	if [[ "$state" == "up" ]]; then
		if [[ -f "$server_info" ]]; then	#state changed from down to up
			first_down="$( grep "first_down:" "$server_info" | egrep -o "$date_regex" )"
			total_downtime="$( downtime_calc )"

			rm -f "$server_info"
			save_report
		fi
	elif [[ "$state" == "down" ]]; then
		if [[ ! -f "$server_info" ]]; then	#state changed from up to down
			first_down="$date $time"

			total_downtime="<5m"

			echo "first_down: $first_down" > "$server_info"
			save_report
		else								#state still down
			last_notify="$( grep "last_notify:" "$server_info" | egrep -o "$date_regex" )"
			secs=$(( $( date -d "$date $time" '+%s' ) - $( date -d "$last_notify" '+%s' ) ))
			hours_since_notify=$(( secs / 3600 ))

			if [ $hours_since_notify -ge 1 ]; then		#if it's been more than 1hr since the last notification, notify again
				first_down="$( grep "first_down:" "$server_info" | egrep -o "$date_regex" )"
				total_downtime="$( downtime_calc )"

				save_report
			fi
		fi
	elif [[ "$state" == "error" ]]; then
		if [[ -f "$server_info" ]]; then
			last_seen_state="down"
			first_down="$( grep "first_down:" "$server_info" | egrep -o "$date_regex" )"
		else
			last_seen_state="up"
			first_down="N/A"
		fi
		total_downtime="Unknown"
		save_report
		echo "Last State Seen: $last_seen_state" >> "$report_tempfile"
	fi
}

publish_report()
{
	response_tempfile="./$( cat /dev/urandom | tr -cd [:xdigit:] | head -c 10 )"
	curl -s https://ghostbin.com/paste/new -i \
	-A "compilingEntropy - Uptime Monitor" \
	--data-urlencode text"@$report_tempfile" \
	--data-urlencode expire='15d' \
	--data-urlencode lang='text' > "$response_tempfile"

	http_code="$( grep "HTTP" "$response_tempfile" | tail -1 | egrep -o "[0-9]{3}" )"

	if [[ "$http_code" != "303" ]]; then
		paste="/paste/a6ofs"
	else
		paste="$( grep "Location:" "$response_tempfile" | egrep -o "\/paste\/[[:alnum:]]+" )"
	fi

	rm -f "$response_tempfile" "$report_tempfile"

	url="https://ghostbin.com$paste/raw"
}

push_report()
{
	server="$1"
	port="$2"
	state="$3"
	url="$4"

	#fill in airgram info below
	response_tempfile="./$( cat /dev/urandom | tr -cd [:xdigit:] | head -c 9 )"
	curl -s http://api.airgramapp.com/1/broadcast \
	-u "" \
	--data-urlencode msg="Server: $server:$port Current State: $state" \
	--data-urlencode url="$url" > "$response_tempfile"

	is_okay="$( grep -c '"status": "ok"' "$response_tempfile" )"
	rm -f "$response_tempfile"
	if [ $is_okay -eq 1 ] && [ -f "$server_info" ]; then
		last_notify="$date $time"
		if [ "$( grep "last_notify:" "$server_info" | egrep -c "$date_regex" )" -eq 1 ]; then
			sed -i -r "/last_notify: $date_regex/d" "$server_info"
		fi
		echo "last_notify: $last_notify" >> "$server_info"
	fi
}

log()
{
	server="$1"
	port="$2"
	state="$3"

	logfile="./uptime_log.csv"

	if [[ ! -f "$logfile" ]]; then
		echo "server,port,date,time,state" > "$logfile"
	fi
	echo "$server,$port,$date,$time,$state" >> "$logfile"
}

check_server()
{
	server="$1"
	port="$2"

	exitcode="$( is_down "$server" "$port" )"
	if [ $exitcode -eq 1 ]; then
		#down
		state="down"
	elif [ $exitcode -eq 0 ]; then
		#up
		state="up"
	else
		#error
		state="error"
	fi

	generate_report "$server" "$port" "$state"
	if [ $should_notify -eq 1 ]; then
		publish_report
		push_report "$server" "$port" "$state" "$url"
	fi

	log "$server" "$port" "$state"
}

#check whatever ports with whatever server
server="example.com"
ports=('22' '80' '443')
for port in "${ports[@]}"; do
	check_server "$server" "$port"
done
