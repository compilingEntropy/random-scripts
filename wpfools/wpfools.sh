#!/bin/bash

###
# 
# This code: https://github.com/compilingEntropy/random-scripts/blob/master/wpfools/wpfools.sh
# 
# This is a rewrite for wptool. Original source: https://code.google.com/p/wptool/
# Original code by https://code.google.com/p/wptool/people/list
# The idea is to replace as much as possible of the backend for this tool with wpcli
# (https://github.com/wp-cli/wp-cli)
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
# > 'wp-content_stock' won't be kept if there's already a wp-content present, under 'wpcore'
# > old Wordpress files are no longer in 'core_$timestamp', they'll now be in 'oldwp_$timestamp'
# > 'wpstats' does not run tests on index.php or wp-admin/index.php
# > 
# 
# 
# 
# 
###

###
# 
# Things to fix
# ----------------------------
# 
# > replace wpcore() with wpcli core, maybe (more testing required)
# > wpht() in general just needs some serious QA testing, r&d
# > wpfix() needs QA
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


######untested code below#######


wptheme()
{
	if [[ "$1" == "--help" || "$1" == "-h" || "$1" == "help" ]]; then
		echo "
	activate          Activate a theme.
	delete            Delete a theme.
	disable           Disable a theme in a multisite install.
	enable            Enable a theme in a multisite install.
	fresh             Install twentyfifteen and set as active theme.
	get               Get a theme.
	install           Install a theme.
	is-installed      Check if the theme is installed.
	list              Get a list of themes.
	mod               Manage theme mods.
	path              Get the path to a theme or to the theme directory.
	search            Search the wordpress.org theme repository.
	status            See the status of one or all themes.
	update            Update one or more themes.
	use               Install and activate a theme.

	-s                Set only stylesheet: wptheme -s twentyfifteen
	-t                Set only template: wptheme -t twentyfifteen
		"
	elif [[ -z "$1" ]]; then
		echo -e "\nCurrent themes:\n"
		#wpcli theme list --status="active"	#broken
		echo -e "\tstylesheet:\t$(wpcli option get stylesheet)"
		echo -e "\ttemplate:\t$(wpcli option get template)"
		echo -e "\nAvailable themes:\n"
		wpcli theme list
	elif [[ "$1" == "fresh" ]]; then
		wpcli theme install twentyfifteen
		wpcli theme activate twentyfifteen
	elif [[ "$1" == "use" ]]; then
		wpcli theme install "$2"
		wpcli theme activate "$2"
	elif [[ "$1" == "-s" ]]; then
		wpcli option update stylesheet "$2"
	elif [[ "$1" == "-t" ]]; then
		wpcli option update template "$2"
	else
		wpcli theme "$@"
	fi
}

wpfix()
{
	if [[ "$1" == "--help" || "$1" == "-h" || "$1" == "help" ]]; then
		echo -e "This tool runs various built-in Wordpress functions and fixes.\n\nUsage:\n\n\twpfix\n"
		return
	fi

	wpcli cache flush
	wpcli db repair
	wpcli db optimize
	wpcli core update-db

	#not working?
	struct="$( wpcli option get permalink_structure )"
	if [[ -n "$struct" ]]; then
		wpcli rewrite structure "$struct" --hard
	else
		#something
		sleep 0
	fi
}

#unfinished maybe
wpstats()
{
	echo -e "
	WP version:	$( wpcli core version )
	UserID 1:	$( wpcli "user get 1 --field='display_name'" )
	home:		$( wpcli option get home )
	siteurl:	$( wpcli option get siteurl )
	stylesheet:	$( wpcli option get stylesheet )
	template:	$( wpcli option get template )
	"
}

wpurl()
{
	if [[ -z "$1" ]]; then
		echo -e "
	home:		$( wpcli option get home )
	siteurl:	$( wpcli option get siteurl )
		"
	elif [[ "$1" == "--help" || "$1" == "-h" || "$1" == "help" ]]; then
		echo -e "This tool returns the current URL settings in the database, or updates them to a specified URL.

Usage:

	wpurl [URL]

	URL
		specify a URL to change the site to. If the URL does not start with 'http://' or 'https://' it will automatically append 'http://'.
		"
	else
		if [[ "$1" =~ (^http[s]?://.*) ]]; then
			url="$1"
		else
			url="http://$1"
		fi
		wpcli option update siteurl "$url"
		wpcli option update home "$url"
	fi
}

#FIX
#hopefully this will be replaced by a feature I have requested, quick and dirty until then
wpht()
{
	if [[ -f ./.htaccess ]]; then
		cp ./.htaccess ./.htaccess_"$(now)"
	fi

	#double check this
	struct="$( wpcli option get permalink_structure )"
	if [[ -n "$struct" ]]; then
		wpcli rewrite structure "$struct" --hard
	else
		#remove everything between BEGIN and END
		#sed -i '/# BEGIN WordPress/,/# END WordPress/ d' ./.htaccess
		sleep 0
	fi
}

wpdb()
{
	#FIX
	#would like a better way of doing this line
	read -r dbhost dbname dbpass dbuser dbprefix <<< "$( cat wp-config.php | egrep "^[^/].*[\"']DB_(NAME|USER|PASSWORD|HOST[^_])|table_prefix" | sort -d | sed "s/.*[\"']\(.*\)[\"'].*;.*/\1/" )"

	#Need to include a optimize/fix option
	if [[ -z "$1" ]]; then
		echo -e "
	DB user:\t$dbuser
	DB pass:\t$dbpass
	DB host:\t$dbhost
	DB name:\t$dbname
	DB prefix:\t$dbprefix
	"
		wpcli core is-installed
		echo "SHOW STATUS WHERE variable_name = 'Threads_running';" | wpcli db query | grep "Threads_running" | sed "s|Threads_running|Active Connections:|g"
		if [ $( wpcli db tables | grep -c ) -lt 1 ]; then
			echo 'Connected with no errors, but no tables that match specified prefix!'
		fi

	elif [[ "$1" == "--help" || "$1" == "-h" || "$1" == "help" ]]; then
		echo "
	cli           Open a mysql console using the WordPress credentials.
	create        Create the database, as specified in wp-config.php
	drop          Delete the database.
	export        Exports the database to a file or to STDOUT.
	import        Import database from a file or from STDIN.
	optimize      Optimize the database.
	query         Execute a query against the database.
	repair        Repair the database.
	reset         Remove all tables from the database.
	tables        List the database tables.
		"
		return
	else
		wpcli db "$@"
	fi
}

wpver()
{
	if [[ $1 == "--help" || $1 == "-h" ]]; then
		echo -e "
This tool returns the current install's file and database versions.

  Usage:

\twpver [option]

\t    -h\n\t\tdisplay this help output
"
		return
	fi

	echo "
	WP version:	$( wpcli core version )
	"
}

wpuser()
{

	if [[ -z "$1" ]]; then
		echo
		wpcli user list
		echo
		return
	elif [[ "$1" == "--help" || "$1" == "-h" || "$1" == "help" ]]; then
		echo -e "
This tool performs various user functions, including returning info for a specified user, changing usernames, passwords, changing a user to an admin, creating new admin users, and deleting users.\n
USERID can be the user login, user email, or actual user ID of the user(s) to update.

Usage:
	wpuser [param [option [param]]]

	USERID
		Returns details about specified user USERID
	USERID -u NAME
		change username of user USERID to NAME
	USERID -p PASS
		change password of user USERID to PASS
	USERID -a
		promote user USERID to admin
	USERID -d [USERID2]
		delete user USERID
		USERID2 is the (optional) user to reassign posts to.
	-n, new
		create new admin user

Additional features:
====================
add-cap          Add a capability for a user.
add-role         Add a role for a user.
create           Create a user.
delete           Delete one or more users from the current site.
generate         Generate users.
get              Get a single user.
import-csv       Import users from a CSV file.
list             List users.
list-caps        List all user's capabilities.
meta             Manage user custom fields.
remove-cap       Remove a user's capability.
remove-role      Remove a user's role.
set-role         Set the user role (for a particular blog).
update           Update a user.
		"
		return
	elif [[ "$2" == "-u" ]]; then
		#yes, I know this gives a warning and does not work. I'm assuming there's a reason for that warning,
		#and not implementing a workaround because I'm also assuming that the reason is a good one. Rather
		#than not implementing this feature at all, I'm including the command that should work instead to
		#show users that it's not a good idea to update the username.
		wpcli "user update "$1" --user_login="$3""
		return
	elif [[ "$2" == "-p" ]]; then
		wpcli "user update "$1" --user_pass="$3""
		return
	elif [[ "$2" == "-a" ]]; then
		wpcli "user add-role "$1" administrator"
		return
	elif [[ "$2" == "-d" ]]; then
		if [[ -n "$3" ]]; then
			wpcli "user delete "$1" --reassign="$3""
		else
			wpcli user delete "$1"
		fi

		return
	elif [[ "$1" == "-n" || "$1" == "new" ]]; then
		echo

		default="deleteme"
		unset username
		read -rp "Username [$default]: " username
		if [[ -z "$username" ]]; then
			username="$default"
		fi

		default="deleteme@example.com"
		unset email
		read -rp "Email [$default]: " email
		if [[ -z "$email" ]]; then
			email="$default"
		fi

		unset default
		unset password
		read -rp "Password [randomly generated]: " password

		if [[ -z "$password" ]]; then
			wpcli "user create "$username" "$email" --role=administrator"
		else
			wpcli "user create "$username" "$email" --role=administrator --user_pass="$password""
		fi

		echo
		return
	elif [[ -z "$2" ]]; then
		wpcli user get "$1"
		return
	else
		#pipe output to sed to fix usage text, but this breaks read prompts like in wpcli user delete :(
		wpcli user "$@" # | sed "s|wp user|wpuser|g"
		return
	fi
}













#
#
#
#
#Code beyond this point has not been reviewed, enter at your own risk...
#
#Commits welcome :)
#
#
#
#















wpplug()
{
	echo
	folder=wp-content/plugins
	if [[ $1 == "--help" || $1 == "-h" ]]; then
		echo -e "This tool does basic plugin functions, such as displaying active and available plugins, or disabling them all.\n"
		echo -e "Usage:\n"
		echo -e "\twpplug [option]\n"
		echo -e "\t-d\n\t\tdisable all plugins by renaming the plugins folder\n"
		return
	elif [[ ! -d $folder ]]; then echo "The $folder folder was not found"! && return 9
	elif [[ ! -f wp-config.php ]]; then echo Could not find wp-config.php! && return 9
	fi
	if [[ $1 == "-d" ]]; then
		temp=$(now)
		mv $folder "$folder"_$temp && echo "Moved plugins to $folder"_$temp...
	elif [[ -z $1 ]]; then
		echo -e "Active plugins:\n"
		wpconn "wpplug"
		active=$(echo "$myconn" | tail -n +2)
		php-cli -r "print_r(unserialize('$active'));" | grep "=>" | sed "s|.*=> \(.*\)|\t\1|"
		echo
		echo -e "Available plugins:\n"
		ls -F $folder |grep "/"|grep -v "^\."|sed "s|^\(.*\)/|\t\1|" #ls -A is overwritten by default $LS_OPTIONS in alias
	fi
	echo
}



wptool()
{
  echo -e "
  _       ______  __              __
 | |     / / __ \/ /_____  ____  / /
 | | /| / / /_/ / __/ __ \/ __ \/ /
 | |/ |/ / ____/ /_/ /_/ / /_/ / /
 |__/|__/_/    \__/\____/\____/_/
					a toolkit production

  WPtool $wptoolv is suite of bash functions to administer Wordpress installs.
  It assumes you are running said functions in the site's root folder. Each
  command listed below each have a -h option for more specific information:
  
	wpstats:  basic overview
	wpurl:    URL tools
	wptheme:  theme tools
	wpdb:     db tools
	wpuser:   user tools
	wpplug:   plugin tools
	wpht:     .htaccess generator
	wpcore:   core replacement tools
	wpfix:    built-in WP fixes
	wpver:    returns version info
"
}
