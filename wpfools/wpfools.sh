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
# > wpuser -u does not work for reasons.
# > wpver() does not get db version, and therefore wpcore() can't download db version
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
# > be consistent with returns
# > remove -e from echo when not necessary
# 
# 
# 
###




#untested on old versions of wordpress
wpenv()
{
	#set appropriate wp binary env
	if [[ -f ./wp-includes/version.php ]]; then
		wp_version="$( php-cli -r 'require_once("./wp-includes/version.php"); echo "$wp_version";' )"
		#non-intuitive, but this checks if the version is greater than or equal to 3.5.2
		if [[ "$( echo -e "3.5.2\n$wp_version" | sort -V | head -n 1 )" == "3.5.2" ]]; then
			#greater than or equal to 3.5.2
			wpcli()
			{
				/usr/php/54/usr/bin/php-cli -c /etc/wp-cli/php.ini /usr/php/54/usr/bin/wp "$@"
			}
		else
			#less than 3.5.2
			wpcli()
			{
				/usr/php/54/usr/bin/php-cli /usr/php/54/usr/bin/wp-compat "$@"
			}
		fi
	else
		echo "Unable to detect Wordpress version, assuming > 3.5.2."
		wpcli()
		{
			/usr/php/54/usr/bin/php-cli -c /etc/wp-cli/php.ini /usr/php/54/usr/bin/wp "$@"
		}
	fi
}

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
		-h
		display this help output
"
	}

	##TODO: fix the version stuff, sanitize
	#Download new set of files matching current file version
	fileVersion()
	{
		version="$( wpver -q )"
		wpfile="wordpress-$version.tar.gz"
	}
	#Download new set of files matching current database version
#	databaseVersion()
#	{
#		version="$( wpver -q | awk '{print $3}' )"
#		wpfile="wordpress-$version.tar.gz"
#	}
	#Download new set of files matching user specified version
	selectedVersion()
	{
		#Sanitize user input
		if [[ ! "$arg" =~ $version_regex ]]; then
			echo 'Version specified is not valid!'
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
	#elif [[ "$arg" == "db" || "$arg" == "database" ]]; then
	#	databaseVersion
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
	wpenv

	if [[ "$1" == "--help" || "$1" =~ -[hH] || "$1" == "help" ]]; then
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
	update [--all]    Update one or more themes.
	use               Install and activate a theme.

	-s                Set only stylesheet: wptheme -s twentyfifteen
	-t                Set only template: wptheme -t twentyfifteen
		"
	elif [[ -z "$1" ]]; then
		echo
		wpcli theme status
		echo "
Details:
  stylesheet:   $(wpcli option get stylesheet)
  template:     $(wpcli option get template)
		"
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
	wpenv

	if [[ "$1" == "--help" || "$1" =~ -[hH] || "$1" == "help" ]]; then
		echo -e "This tool runs various built-in Wordpress functions and fixes."
		return
	fi

	wpcli cache flush
	wpcli db repair | grep -v "OK"
	wpcli db optimize | grep -v "OK"
	wpcli core update-db
	#wpcli rewrite flush --hard
	wpcli transient delete-expired


#	###HARD FIXES###
#	#probably gonna add a line by line prompt for these.
#
#	wpcli role reset
#	wpcli media regenerate --yes
#	wpcli plugin update --all
#	wpcli theme update --all
#	wpcli core update
#	wpcli transient delete-all
#
#	#delete spam comments
#	wp comment delete $( wp comment list --status=spam --format=ids )
#	#delete unapproved comments
#	wp comment delete $( wp comment list --status=unapproved --format=ids )
}

#unfinished maybe
wpstats()
{
	wpenv

	#perhaps do a wpcli core check-update alongside the version
	#maybe check some things about the install such as checksums, database connectivity, etc
	echo -e "
	WP version:   $( wpcli core version )
	UserID 1:     $( wpcli user get 1 --field='display_name' )
	home:         $( wpcli option get home )
	siteurl:      $( wpcli option get siteurl )
	stylesheet:   $( wpcli option get stylesheet )
	template:     $( wpcli option get template )
	"
	wpcli core is-installed || echo
}

wpurl()
{
	wpenv

	if [[ -z "$1" ]]; then
		echo -e "
	home:      $( wpcli option get home )
	siteurl:   $( wpcli option get siteurl )
		"
	elif [[ "$1" == "--help" || "$1" =~ -[hH] || "$1" == "help" ]]; then
		echo -e "This tool returns the current URL settings in the database, or updates them to a specified URL.

	wpurl [URL]
		"
	else
		if [[ "$1" =~ (^http[s]?://.*) ]]; then
			url="$1"
		else
			url="http://$1"
			echo "Using: $url"
		fi
		wpcli option update siteurl "$url"
		wpcli option update home "$url"
	fi
}

#FIX
#hopefully this will be replaced by a feature I have requested, quick and dirty until then
wpht()
{
	wpenv

	if [[ -f ./.htaccess ]]; then
		cp ./.htaccess ./.htaccess_"$( now )"
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
	wpenv

	#get some database variables from wp-config.php
	if [[ -f "./wp-config.php" ]]; then
		dbuser="$( php-cli -r 'require_once("./wp-config.php"); echo constant("DB_USER");' )"
		dbpass="$( php-cli -r 'require_once("./wp-config.php"); echo constant("DB_PASSWORD");' )"
		dbhost="$( php-cli -r 'require_once("./wp-config.php"); echo constant("DB_HOST");' )"
		dbname="$( php-cli -r 'require_once("./wp-config.php"); echo constant("DB_NAME");' )"
		dbprefix="$( php-cli -r 'require_once("./wp-config.php"); echo "$table_prefix";' )"
	else
		echo "Unable to locate the wp-config.php file, attempting to continue..."
	fi

	if [[ -z "$1" ]]; then
		echo -e "
	DB user:    $dbuser
	DB pass:    $dbpass
	DB host:    $dbhost
	DB name:    $dbname
	DB prefix:  $dbprefix
		"
		wpcli core is-installed || echo
		wpcli db query "SHOW STATUS WHERE variable_name = 'Threads_running';" | grep "Threads_running" | sed "s|Threads_running|Active Connections:|g"
		if [ $( wpcli db tables | egrep -c "^$dbprefix" ) -lt 1 ]; then
			echo 'Connected with no errors, but no tables that match specified prefix!'
		fi

	elif [[ "$1" == "--help" || "$1" =~ -[hH] || "$1" == "help" ]]; then
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
	wpenv

	if [[ "$1" == "--help" || "$1" =~ -[hH] || "$1" == "help" ]]; then
		echo -e "
This tool returns the current install's version.
		"
		return
	elif [[ "$1" == "-q" ]]; then
		wpcli core version
	else
		echo "
	WP version:	$( wpcli core version )
		"
	fi
}

wpuser()
{
	wpenv

	if [[ -z "$1" ]]; then
		echo
		wpcli user list
		echo
		return
	elif [[ "$1" == "--help" || "$1" =~ -[hH] || "$1" == "help" ]]; then
		echo -e "
This tool performs various user functions, including returning info for a specified
user, changing usernames, passwords, changing a user to an admin, creating new admin
users, and deleting users.
USERID can be the user login, user email, or actual user ID of the user(s) to update.

Usage:
	wpuser [param [option [param]]]

	USERID
		Returns details about specified user USERID
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
		#Yes, I know this gives a warning and does not work. I'm assuming there's a reason for that warning,
		#and not implementing a workaround because I'm also assuming that the reason is a good one. Rather
		#than not implementing this feature at all, I'm including the command that should work instead to
		#show users that it's not a good idea to update the username. This option is not in the help text
		#and should be considered deprecated; it is included only for legacy purposes.
		wpcli user update "$1" --user_login="$3" 
		return
	elif [[ "$2" == "-p" ]]; then
		wpcli user update "$1" --user_pass="$3" 
		return
	elif [[ "$2" == "-a" ]]; then
		wpcli user add-role "$1" administrator 
		return
	elif [[ "$2" == "-d" ]]; then
		if [[ -n "$3" ]]; then
			wpcli user delete "$1" --reassign="$3" 
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
			wpcli user create "$username" "$email" --role=administrator 
		else
			wpcli user create "$username" "$email" --role=administrator --user_pass="$password"
		fi

		unset password
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

wpplug()
{
	wpenv

	if [[ -z "$1" ]]; then
		echo
		wpcli plugin status
		echo
		return
	elif [[ "$1" == "--help" || "$1" =~ -[hH] || "$1" == "help" ]]; then
		echo -e "
Basic plugin functions.

	-a, activate [--all]     Activate one or more plugins.
	-d, deactivate [--all]   Deactivate one or more plugins.
	delete                   Delete plugin files.
	get                      Get a plugin.
	install                  Install a plugin.
	is-installed             Check if the plugin is installed.
	list                     Get a list of plugins.
	path                     Get the path to a plugin or to the plugin directory.
	search                   Search the wordpress.org plugin repository.
	status                   See the status of one or all plugins.
	toggle                   Toggle a plugin's activation state.
	uninstall                Uninstall a plugin.
	-u, update [--all]       Update one or more plugins.
		"
		return
	elif [[ "$1" == "-d" ]] || [[ "$1" == "deactivate" && (( "$2" == "-all" || "$2" == "--all" )) ]]; then
		active_plugins=( $( wpcli plugin list --status=active --fields=name | sed -n "2,$ p" ) )
		if [[ -z "${active_plugins[@]}" ]]; then
			echo 'No plugins active!'
		else
			wpcli plugin deactivate ${active_plugins[@]}
		fi
	elif [[ "$1" == "-a" ]] || [[ "$1" == "activate" && (( "$2" == "-all" || "$2" == "--all" )) ]]; then
		#The point of this is to check if someone ran a deactivate --all already, and if so, reactivate
		#only the plugins that were deactivated the first time. Otherwise, activate all plugins. If you
		#run this twice, it'll activate all plugins regardless.
		inactive_plugins=( $( wpcli plugin list --status=inactive --fields=name | sed -n "2,$ p" ) )
		if [[ -z "${active_plugins[@]}" ]]; then
			if [[ -n "${inactive_plugins[@]}" ]]; then
				wpcli plugin activate ${inactive_plugins[@]}
			else
				echo 'All plugins active!'
			fi
		else
			wpcli plugin activate ${active_plugins[@]}
			unset active_plugins
		fi
	elif [[ "$1" == "-u" ]] || [[ "$1" == "update" && "$2" == "-all" ]]; then
		wpcli plugin update --all
	else
		#pipe output to sed to fix usage text, but this breaks read prompts like in wpcli user delete :(
		wpcli user "$@" # | sed "s|wp user|wpuser|g"
		return
	fi
}

wphelp()
{
  echo -e "
  The following are bash functions that call /usr/bin/wp to administer Wordpress
  installs. It assumes you are running said functions in the site's root folder.
  Most commands listed below have a -h option for more specific information:
  
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
