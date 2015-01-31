#!/bin/bash

###
# 
# This is a rewrite for wptool. Original source: https://code.google.com/p/wptool/
# Original code by https://code.google.com/p/wptool/people/list
# 
# 
# As with the original, wptool is suite of bash functions to administer Wordpress installs.
# This rewrite was done with stability and  maintainability in mind. The intent is to keep
# the syntax and functionality the same as the original to the extent that it can be treated
# as a drop-in replacement. Any differences in functionality or syntax will be documented in
# the code, and in the 'differences' section below. This branch will be maintained
# seperately from the original as well; the version this is built off of is 1.7.1.2.
# 
###


###
# 
# Differences in functionality
# ----------------------------
# 
# >'wp-content_stock' won't be kept if there's already a wp-content present, under 'wpcore'
# >old Wordpress files are no longer in 'core_$timestamp', they'll now be in 'oldwp_$timestamp'
# 
# 
# 
# 
# 
# 
###

version_regex="^([[:digit:]]\.[[:digit:]]{1,2}|[[:digit:]]\.[[:digit:]]\.[[:digit:]]{1,2})$"
sha1_regex="\b[[:xdigit:]]{40}\b"

now() 
{
  date -u +"%Y%m%d-%H%M%S"
}

wpcore()
{
	arg="$1"

	#Display help information
	helpText()
	{
		echo -e "
This tool downloads the latest core, a new core of the current version, or a
specified version.

Usage:

	wpcore [VERSION]

	    <blank>
		download the latest stable version of the Wordpress core
	    #.#.#
		download version VERSION of the Wordpress core
	    cur
		download new set of files matching current file version
	    db
		download set of files matching current database version
	    -h
		display this help output
"
	}

	##TODO: fix the version stuff, sanitize
	#Download new set of files matching current file version
	fileVersion()
	{
		version="$(wpver -q | awk '{print $1}')"
		wpfile="wordpress-$version.tar.gz"
	}
	#Download new set of files matching current database version
	databaseVersion()
	{
		version="$(wpver -q | awk '{print $3}')"
		wpfile="wordpress-$version.tar.gz"
	}
	#Download new set of files matching user specified version
	selectedVersion()
	{
		#Sanitize user input
		if [[ ! "$arg" =~ $version_regex ]]; then
			echo "Version specified is not valid!"
			return 9
		fi

		version="$arg"
		wpfile="wordpress-$version.tar.gz"
	}
	#Download new set of files matching current file version
	latestVersion()
	{
		version="latest"
		wpfile="latest.tar.gz"
	}

	#Download Wordpress package
	getFile()
	{
		#verifies the file with an sha1 checksum
		checkSha1()
		{
			if [[ -f "./$wpfile" ]]; then
				sha1_remote="$( curl -sS "https://wordpress.org/$wpfile.sha1" | egrep -o "$sha1_regex" )"
				if [[ "$sha1_remote" =~ $sha1_regex ]]; then
					#successfully got remote sha1 checksum
					sha1_local="$( sha1sum "./$wpfile" | egrep -o "$sha1_regex" )"
					if [[ "$sha1_local" =~ $sha1_regex ]]; then
						#successfully got local sha1 checksum
						if [[ "$sha1_local" == "$sha1_remote" ]]; then
							#checksum match
							return 0
						else
							#checksum mismatch
							echo -en '\nChecksum mismatch!'
							rm -f "./$wpfile"
							((i++))
							return 9
						fi
					else
						echo -en "\nError: Unable to get local sha1 checksum"
						rm -f "./$wpfile"
						return 9
					fi
				else
					echo -en "\nError: Unable to get remote sha1 checksum"
					return 9
				fi
			else
				#file does not exist
				echo -n "Error: Download failed"
				((i++))
				return 9
			fi
		}

		if [[ "$version" == "latest" ]]; then
			echo -n "Downloading latest Wordpress..."
		else
			echo -n "Downloading Wordpress $version..."
		fi

		if [[ ! -f "./$wpfile" ]]; then
			wget -q "https://wordpress.org/$wpfile"
		fi

		TRIES=3

		i=0
		checkSha1
		#try a few times if it fails
		while (( $? != 0 && "$i" < "$TRIES" )); do
			echo -en "\nRetrying..."
			wget -q "https://wordpress.org/$wpfile"
			checkSha1
		done

		#too many retries
		if (( "$i" >= "$TRIES" )); then
			echo -e "\nFatal Error: Could not download Wordpress."
			return 9
		fi

		echo "done."
		return 0
	}

	#Extract Wordpress
	extractWordpress()
	{
		##build list of Wordpress files in pwd
		#build list of possible wp files
		possible_files=( $( tar -ztf "./$wpfile" | sed -e "s|^wordpress/||g" -e "s|/.*|/|g" -e "/^[[:space:]]*$/d" | sort -u ) )
		possible_files=( "${possible_files[@]}" "wp-config.php" )
		#build list of actual files
		for file in "${possible_files[@]}"; do
			if [[ -e "./$file" ]]; then
				actual_files=( "${actual_files[@]}" "$file" )
			fi
		done

		old_wp="oldwp_$( now )"

		#rebuild a temp array without index.php
		actual_files_temp=( ${actual_files[@]/index.php/} )

		#if there's old stuff that isn't index.php
		if (( "${#actual_files_temp[@]}" > 0 )); then
			echo -n "Moving old Wordpress files..."

			#create old Wordpress folder
			if [[ ! -d "./$old_wp/" ]]; then
				mkdir "./$old_wp/"
			fi

			#move old Wordpress files down into a new subdir
			for file in "${actual_files[@]}"; do
				if [[ -e "./$file" ]]; then
					rsync -aq "./$file" "./$old_wp/$file"
					if [[ $? == 0  && -e "./$old_wp/$file" ]]; then
						rm -rf "./$file"
					fi
				fi
			done

			echo "done."
		fi

		echo -n "Extracting Wordpress..."
		
		#extract the new Wordpress files into pwd
		tar -xf "./$wpfile" --strip-components=1

		didFail="0"
		#test for successful extraction
		for file in ${possible_files[@]/wp-config.php/}; do
			if [[ ! -e "./$file" ]]; then
				##TODO: retry extracting failed file
				echo -en "\nError extracting $file"'!'
				didFail="1"
			fi
		done

		if (( "$didFail" == 1 )); then
			echo -e "\nFatal Error: Could not extract $file."
			return 9
		fi

		#remove $wpfile
		rm -f "./$wpfile"

		echo "done."

		#if there was a wp-content dir in the old install, copy it into pwd and burn stock wp-content
		if [[ -d "./$old_wp/wp-content/" ]]; then
			echo -n "Moving in old wp-content..."

			rm -rf "./wp-content/"
			rsync -aq "./$old_wp/wp-content/" "./wp-content/"

			echo "done."
		fi		

		#move in old wp-config.php if it exists
		if [[ -f "./$old_wp/wp-config.php" ]]; then
			echo -n "Moving in old wp-config.php..."

			if [[ -f "./wp-config.php" ]]; then
				rm -f "./wp-config.php"
			fi
			rsync -aq "./$old_wp/wp-config.php" "./wp-config.php"

			echo "done."
		else
			#otherwise, move in wp-config-sample.php
			mv "./wp-config-sample.php" "./wp-config.php"
		fi

		return 0
	}

	#process user input
	if [[ "$arg" == "--help" || "$arg" =~ -[hH] ]]; then
		helpText
		return 0
	elif [[ "$arg" == "cur" || "$arg" == "file" ]]; then
		fileVersion
	elif [[ "$arg" == "db" || "$arg" == "database" ]]; then
		databaseVersion
	elif [[ "$arg" =~ $version_regex ]]; then
		selectedVersion
	elif [[ "$arg" == "latest" || -z "$arg" ]]; then
		latestVersion
	else
		echo 'Unknown Wordpress version specified!'
		echo "Wordpress versions can be either #.# or #.#.#"
		helpText
		return 9
	fi

	getFile
	if (( $? != 0 )); then
		return 9
	fi
	extractWordpress
}



##TODO: not reviewed
wpver()
{
	arg="$1"
	if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
		echo -e "
This tool returns the current install's file and database versions.

Usage:

\twpver [option]

\t    -q\n\t\tdisplay abbreviated version output
\t    -h\n\t\tdisplay this help output
"
		return 0
	fi
	local filever="Unknown"
	local dbver="Unknown"
	local dbver_files="Unknown"
	if [[ -f wp-includes/version.php ]]; then
		filever=$(cat wp-includes/version.php | grep "wp_version " | sed "s/.*'\(.*\)'.*/\1/")
	fi
	wpconn "wpdbver"
	if [[ $? == 0 && $myconn != "ERROR"* ]]; then
		dbver=$(echo -e "$myconn" | tail -1)
		dbver_files=$(curl -Ss https://codex.wordpress.org/FAQ_Installation | grep "= $dbver" | head -1 | awk '{print $1}')
	fi
	if [[ "$1" == "-q" ]]; then
		echo -e "$filever $dbver $dbver_files"
	else
		echo -e "\n\tWP version:\t$filever\n\tDB version:\t$dbver (up to $dbver_files)\n"
	fi
}
