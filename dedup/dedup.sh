#!/bin/bash

#this may never get finished, but see the last few lines if you care about deduping files
#each method has advantages and disadvantages.

params=( $( for arg in $@; do echo "$arg"; done ) )
slow=0
fast=0
first=0
last=0
sort=0

#parse options
i=0
for arg in "${params[@]}"; do
	if [[ "$arg" == "-f" ]]; then
		infile="${params[$i+1]}"
	fi
	if [[ "$arg" == "-o" ]]; then
		outfile="${params[$i+1]}"
	fi
	if [[ "$arg" == "-s" ]]; then
		slow=1
	fi		
	if [[ "$arg" == "-q" ]]; then
		fast=1
	fi
	if [[ "$arg" == "-b" ]]; then
		first=1
	fi
	if [[ "$arg" == "-l" ]]; then
		last=1
	fi
	if [[ "$arg" == "-u" ]]; then
		sort=1
	fi
	((i++))
done

mode=0
if [ $sort = 1 ]; then
	mode=$(( $mode + 4 ))
fi
if [ $sort = 1 ]; then
	mode=$(( $mode + 4 ))
fi

sort -u ./$oldfile > ./$newfile
awk '!n[$0]++' ./$oldfile > ./$newfile
cat -n ./$oldfile | sort -uk2 | sort -nk1 | cut -f2- > ./$newfile