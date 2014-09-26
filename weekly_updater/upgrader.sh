#!/bin/bash

#this is a script to do 'apt-get dist-upgrade' and send you the results via an airgram push notification (http://www.airgramapp.com)
#fill in your airgram credentials below
#I'm guessing this could easily be modified to use pushover as well.

#cron this at '00 01 * * 1'
server_name=""

export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export DEBIAN_FRONTEND="noninteractive"

echo "~# apt-get update" > "./upgrade.log"
apt-get -y update &>> "./upgrade.log"

echo -e "\n~# apt-get dist-upgrade" >> "./upgrade.log"
apt-get -sV dist-upgrade > "./upgrade_sim.txt"
apt-get -y dist-upgrade &>> "./upgrade.log"

echo -e "\n~# apt-get autoremove" >> "./upgrade.log"
apt-get -sV autoremove > "./autoremove_sim.txt"
apt-get -y autoremove &>> "./upgrade.log"

echo -e "\n~# apt-get clean" >> "./upgrade.log"
apt-get -y clean > "./clean.txt"
cat "./clean.txt" &>> "./upgrade.log"

unset DEBIAN_FRONTEND


##clean up output files
#remove the simulated events
sed -i -r '/[0-9]+ upgraded, [0-9]+ newly installed, [0-9]+ to remove and [0-9]+ not upgraded\./,$d' "./upgrade_sim.txt"
sed -i -r '/[0-9]+ upgraded, [0-9]+ newly installed, [0-9]+ to remove and [0-9]+ not upgraded\./,$d' "./autoremove_sim.txt"

echo "$( date '+%F %T' )" > "./report.txt"
echo "Upgrade summary:" >> "./report.txt"

#remove 'reading', 'building' stages, combine results
echo -e "\ndist-upgrade" >> "./report.txt"
change="$( tac "./upgrade_sim.txt" | sed '/Reading state information\.\.\./,$d' | tac )"
if [[ "$change" == "" ]]; then
        change="No change made."
fi
echo "$change" >> "./report.txt"

echo -e "\nautoremove" >> "./report.txt"
change="$( tac "./autoremove_sim.txt" | sed '/Reading state information\.\.\./,$d' | tac )"
if [[ "$change" == "" ]]; then
        change="No change made."
fi
echo "$change" >> "./report.txt"

echo -e "\nclean" >> "./report.txt"
change="$( tac ./clean.txt | sed '/Reading state information\.\.\./,$d' | tac )"
if [[ "$change" == "" ]]; then
        change="No change made."
fi
echo "$change" >> "./report.txt"

rm -f ./clean.txt "./autoremove_sim.txt" "./upgrade_sim.txt"

#change 'will be' to 'have been'
sed -i "s|will be|have been|g" "./report.txt"

publish_report()
{
        file="$1"

        response_tempfile="./$( cat /dev/urandom | tr -cd [:xdigit:] | head -c 10 )"
        curl -s https://ghostbin.com/paste/new -i \
        -A "compilingEntropy - Update Reporter" \
        --data-urlencode text"@$file" \
        --data-urlencode expire='15d' \
        --data-urlencode lang='text' > "$response_tempfile"

        http_code="$( grep "HTTP" "$response_tempfile" | tail -1 | egrep -o "[0-9]{3}" )"

        if [[ "$http_code" != "303" ]]; then
                paste="/paste/a6ofs"
        else
                paste="$( grep "Location:" "$response_tempfile" | egrep -o "\/paste\/[[:alnum:]]+" )"
        fi

        rm -f "$response_tempfile"

        url="https://ghostbin.com$paste/raw"
}

push_report()
{
        server_name="$1"
        url="$2"

        #your airgram creds go here
        curl -s http://api.airgramapp.com/1/send \
        -u "" \
        --data-urlencode email="" \
        --data-urlencode msg="Upgrade report for: $server_name" \
        --data-urlencode url="$url" &> /dev/null
}

echo -e "\n\nFor a complete log of the upgrade, see below:\n\n\n\n\n" >> "./report.txt"
cat "./upgrade.log" >> "./report.txt"

publish_report "./report.txt"
rm -f "./report.txt" "./upgrade.log"
push_report "$server_name" "$url"
unset PATH