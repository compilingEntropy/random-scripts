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
# > wpver() does not get db version, and therefore wpcore() can't download db version #note, you can get db version with wpcli core version --extra, possibly implement db version later
# 
# 
# 
###

###
# 
# Things to fix
# ----------------------------
# 
# > wpht() should be fixed once the feature gets implemented
# > wpfix() needs QA
# 
# 
# 
###


version_regex="\b([[:digit:]]\.[[:digit:]]{1,2}|[[:digit:]]\.[[:digit:]]\.[[:digit:]]{1,2})\b"
sha1_regex="\b[[:xdigit:]]{40}\b"

#untested on old versions of wordpress
wpenv()
{
	#set appropriate wp binary env
	if [[ -f ./wp-includes/version.php ]]; then
		wp_version="$( egrep -m 1 -o "$version_regex" ./wp-includes/version.php )"
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

now()
{
	date -u +"%Y%m%d-%H%M%S"
}

wpcore()
{
	arg="$1"

	wpenv

	#clean up cache, this is required because there's a bug that causes update to fail when it tries using a cached file
	rm -rf /home2/"$(whoami)"/.wp-cli/cache/core/*

	#Display help information
	helpText()
	{
		echo "
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

Additional features:
====================
check-update           Check for update via Version Check API. Returns latest version if there's an update, or empty if no update available.
config [--rebuild]     Generate or attempt to rebuild a wp-config.php file.
download               Download core WordPress files.
install                Create the WordPress tables in the database.
is-installed           Determine if the WordPress tables are installed.
language               Modify or activate languages.
multisite-convert      Transform a single-site install into a multi-site install.
multisite-install      Install multisite from scratch.
update                 Update WordPress.
update-db              Update the WordPress database.
verify-checksums       Verify WordPress files against WordPress.org's checksums.
version                Display the WordPress version.
"
	}

	##TODO: fix the version stuff, sanitize
	#Download new set of files matching current file version
	fileVersion()
	{
		version="$( wpcli core version )"
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
	}
	#Download new set of files matching current file version
	latestVersion()
	{
		version="latest"
	}

	updateWordpress()
	{
		#update if we're currently in a wordpress directory, download otherwise
		#basic workaround for incorrectly detected wp installs
		#see https://github.com/wp-cli/wp-cli/issues/1811
		if (( $( wp core is-installed &> /dev/null; echo $? ) == 0 )) && [[ -d ./wp-admin/ ]] && [[ -d ./wp-includes/ ]] && [[ -f ./wp-config.php ]]; then
			if [[ "$version" == "latest" ]]; then
				wpcli core update --force
			else
				wpcli core update --version="$version" --force
			fi
		else
			if [[ "$version" == "latest" ]]; then
				wpcli core download --force
			else
				wpcli core download --version="$version" --force
			fi
		fi
	}

	#Rebuild / generate config config
	buildConfig()
	{
		if [[ "$1" == "--rebuild" ]]; then
			if [[ ! -f ./wp-config.php ]]; then
				echo 'No wp-config.php file available to rebuild!'
				echo "Try: wpcore config"
				return 9
			fi
			#harmless fix so we can use cut in a sec even if their quotes are jacked up
			sed "s/[‘’]/'/g" -i ./wp-config.php

			dbuser="$( grep "DB_USER" ./wp-config.php | cut -d \' -f 4 )"
			dbpass="$( grep "DB_PASSWORD" ./wp-config.php | cut -d \' -f 4 )"
			dbhost="$( grep "DB_HOST" ./wp-config.php | cut -d \' -f 4 )"
			dbname="$( grep "DB_NAME" ./wp-config.php | cut -d \' -f 4 )"
			dbprefix="$( grep "table_prefix" ./wp-config.php | cut -d \' -f 2 )"
			
			temp="wp-config_$( now )"
			mv ./wp-config.php ./"$temp".php

			wpcli core config --dbname="$dbname" --dbuser="$dbuser" --dbpass="$dbpass" --dbhost="$dbhost" --dbprefix="$dbprefix"
			if (( $? != 0 )); then
				mv ./"$temp".php ./wp-config.php
				echo 'Rebuild failed!'
			fi
		else
			if [[ -f ./wp-config.php ]]; then
				echo 'A wp-config.php file already exists!'
				echo "The existing file will be replaced if you continue."
			fi
			echo
			echo "Enter database connection settings below:"

			default="$(whoami)_wp"
			unset dbname
			read -rp "Database name [$default]: " dbname
			if [[ -z "$dbname" ]]; then
				dbname="$default"
			fi

			default="$(whoami)_wp"
			unset dbuser
			read -rp "Username [$default]: " dbuser
			if [[ -z "$dbuser" ]]; then
				dbuser="$default"
			fi

			default="strings /dev/urandom | egrep -o "[[:alnum:]]" | head -n 20 | tr -d "\n""
			unset dbpass
			read -rp "Password [$default]: " dbpass
			if [[ -z "$dbpass" ]]; then
				dbpass="$default"
			fi

			default="localhost"
			unset dbhost
			read -rp "Password [$default]: " dbhost
			if [[ -z "$dbhost" ]]; then
				dbhost="$default"
			fi

			default="_wp"
			unset dbprefix
			read -rp "Password [$default]: " dbprefix
			if [[ -z "$dbprefix" ]]; then
				dbprefix="$default"
			fi


			if [[ -f ./wp-config.php ]]; then
				mv ./wp-config.php ./wp-config_"$( now )".php
			fi

			wpcli core config --dbname="$dbname" --dbuser="$dbuser" --dbpass="$dbpass" --dbhost="$dbhost" --dbprefix="$dbprefix"
			if (( $? != 0 )); then
				wpcli core config --dbname="$dbname" --dbuser="$dbuser" --dbpass="$dbpass" --dbhost="$dbhost" --dbprefix="$dbprefix" --skip-check &> /dev/null
			fi

			unset dbpass
		fi
	}

	#process user input
	if [[ "$1" == "--help" || "$1" =~ ^-[hH]$ ]] || [[ "$1" == "help" && -z "$2" ]]; then
		helpText
		return 0
	elif [[ "$1" == "help" && -n "$2" ]]; then
		wpcli help core "$@"
		return $?
	elif [[ "$arg" == "cur" || "$arg" == "file" ]]; then
		fileVersion
	#elif [[ "$arg" == "db" || "$arg" == "database" ]]; then
	#	databaseVersion
	elif [[ "$arg" =~ $version_regex ]]; then
		selectedVersion
	elif [[ "$arg" == "latest" || -z "$arg" ]]; then
		latestVersion
	elif [[ "$arg" == "config" ]]; then
		buildConfig "$2"
		return $?
	else
		wpcli core "$@"
		return $?
	fi

	updateWordpress || return $?
	wpcli core update-db
}


wptheme()
{
	wpenv

	if [[ "$1" == "--help" || "$1" =~ ^-[hH]$ ]] || [[ "$1" == "help" && -z "$2" ]]; then
		echo "
	activate              Activate a theme.
	delete                Delete a theme.
	disable               Disable a theme in a multisite install.
	enable                Enable a theme in a multisite install.
	fresh                 Install twentyfifteen and set as active theme.
	get                   Get a theme.
	install               Install a theme.
	is-installed          Check if the theme is installed.
	list                  Get a list of themes.
	mod                   Manage theme mods.
	path                  Get the path to a theme or to the theme directory.
	search                Search the wordpress.org theme repository.
	status                See the status of one or all themes.
	-u, update [--all]    Update one or more themes.
	use                   Install and activate a theme.

	-s                    Set only stylesheet: wptheme -s twentyfifteen
	-t                    Set only template: wptheme -t twentyfifteen
		"
	elif [[ "$1" == "help" && -n "$2" ]]; then
		wpcli help theme "$@"
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
	elif [[ "$1" == "-u" ]]; then
		wpcli theme update --all
	else
		wpcli theme "$@"
	fi
}

wpfix()
{
	wpenv

	if [[ "$1" == "--help" || "$1" =~ ^-[hH]$ || "$1" == "help" ]]; then
		echo "This tool runs various built-in Wordpress functions and fixes."
		return 0
	fi
	#not built in, but solves more problems than you'd think
	sed "s/[‘’]/'/g" -i ./wp-config.php

	wpcli cache flush
	wpcli db repair | grep -v "OK"
	wpcli db optimize | grep -v "OK"
	wpcli core update-db
	wpcli transient delete-expired
	wpcore config --rebuild


	###HARD FIXES###
	#would be good to get a menu going
	if [[ "$1" == "--hard" ]]; then
		yes="^[yY][eE]?[sS]?$"
		echo "For the following question, the default answer is no."
		echo "It is recommended that you know what you're doing before you run these, and have a backup."
		unset response

		read -rp "Rewrite htaccess file? [y/n]: " response
		if [[ "$response" =~ $yes ]]; then
			wpht
			unset response
		fi
		read -rp "Reset all roles to default capabilities? [y/n]: " response
		if [[ "$response" =~ $yes ]]; then
			wpcli role reset --all
			unset response
		fi
		wpcli media regenerate --yes #prompts on its own
		read -rp "Update all plugins? [y/n]: " response
		if [[ "$response" =~ $yes ]]; then
			wpcli plugin update --all
			unset response
		fi
		read -rp "Update all themes? [y/n]: " response
		if [[ "$response" =~ $yes ]]; then
			wpcli theme update --all
			unset response
		fi
		read -rp "Update to latest WordPress version? [y/n]: " response
		if [[ "$response" =~ $yes ]]; then
			wpcli core update
			unset response
		fi
		read -rp "Delete all transients? [y/n]: " response
		if [[ "$response" =~ $yes ]]; then
			wpcli transient delete-all
			unset response
		fi
		read -rp "Delete all comments that have been marked as spam? [y/n]: " response
		if [[ "$response" =~ $yes ]]; then
			#delete spam comments
			wp comment delete $( wp comment list --status=spam --format=ids )
			unset response
		fi
		read -rp "Delete all comments that have not been approved? [y/n]: " response
		if [[ "$response" =~ $yes ]]; then
			#delete unapproved comments
			wp comment delete $( wp comment list --status=unapproved --format=ids )
			unset response
		fi
	fi
}

wpstats()
{
	wpenv

	available_version="$( wpcli core check-update --field=version | egrep -m 1 -o $version_regex )"
	wp_version="$( wpcli core version )"
	if [[ -n "$available_version" ]]; then
		version="$wp_version ($available_version available)"
	else
		version="$wp_version"
	fi
	echo "
	WP version:   $version
	user:         $( wpcli user list --fields=id,user_login | sort -n | sed -n "2p" | cut -f 2 2> /dev/null )
	home:         $( wpcli option get home 2> /dev/null )
	siteurl:      $( wpcli option get siteurl 2> /dev/null )
	stylesheet:   $( wpcli option get stylesheet 2> /dev/null )
	template:     $( wpcli option get template 2> /dev/null )
	"
	
	#harmless fix so we can use cut in a sec even if their quotes are jacked up
	sed "s/[‘’]/'/g" -i ./wp-config.php

	dbprefix="$( grep "table_prefix" ./wp-config.php | cut -d \' -f 2 )"
	wpcli core is-installed || echo
	wpcli db query "SHOW STATUS WHERE variable_name = 'Threads_running';" | grep "Threads_running" | sed "s|Threads_running|Active Connections:|g"
	if [[ -z "$dbprefix" ]] && [ $( wpcli db tables 2> /dev/null | egrep -c "^$dbprefix" ) -lt 1 ]; then
		echo 'Connected with no errors, but no tables that match specified prefix!'
	fi
	wpcli core verify-checksums 1> /dev/null
}

wpurl()
{
	wpenv

	if [[ -z "$1" ]]; then
		echo "
	home:      $( wpcli option get home )
	siteurl:   $( wpcli option get siteurl )
		"
	elif [[ "$1" == "--help" || "$1" =~ ^-[hH]$ || "$1" == "help" ]]; then
		echo "This tool returns the current URL settings in the database, or updates them to a specified URL.

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

#	if [[ -f ./.htaccess ]]; then
#		cp ./.htaccess ./.htaccess_"$( now )"
#	fi

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

	if [[ -z "$1" ]]; then
		#get some database variables from wp-config.php
		if [[ -f "./wp-config.php" ]]; then
			#harmless fix so we can use cut in a sec even if their quotes are jacked up
			sed "s/[‘’]/'/g" -i ./wp-config.php

			dbuser="$( grep "DB_USER" ./wp-config.php | cut -d \' -f 4 )"
			dbpass="$( grep "DB_PASSWORD" ./wp-config.php | cut -d \' -f 4 )"
			dbhost="$( grep "DB_HOST" ./wp-config.php | cut -d \' -f 4 )"
			dbname="$( grep "DB_NAME" ./wp-config.php | cut -d \' -f 4 )"
			dbprefix="$( grep "table_prefix" ./wp-config.php | cut -d \' -f 2 )"
		else
			echo "Unable to locate the wp-config.php file, attempting to continue..."
		fi

		echo "
	DB user:    $dbuser
	DB pass:    $dbpass
	DB host:    $dbhost
	DB name:    $dbname
	DB prefix:  $dbprefix
		"

		wpcli core is-installed || echo
		wpcli db query "SHOW STATUS WHERE variable_name = 'Threads_running';" | grep "Threads_running" | sed "s|Threads_running|Active Connections:|g"
		if [[ -z "$dbprefix" ]] && [ $( wpcli db tables 2> /dev/null | egrep -c "^$dbprefix" ) -lt 1 ]; then
			echo 'Connected with no errors, but no tables that match specified prefix!'
		fi
	elif [[ "$1" == "update-db" ]]; then
		wpcli core update-db
	elif [[ "$1" == "--help" || "$1" =~ ^-[hH]$ ]] || [[ "$1" == "help" && -z "$2" ]]; then
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
	update-db     Update the WordPress database.
		"
		return
	elif [[ "$1" == "help" && -n "$2" ]]; then
		wpcli help db "$@"
	else
		wpcli db "$@"
	fi
}

wpver()
{
	wpenv

	if [[ "$1" == "--help" || "$1" =~ ^-[hH]$ || "$1" == "help" ]]; then
		echo "
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
	elif [[ "$1" == "--help" || "$1" =~ ^-[hH]$ ]] || [[ "$1" == "help" && -z "$2" ]]; then
		echo "
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
	elif [[ "$1" == "help" && -n "$2" ]]; then
		wpcli help user "$@"
	elif [[ "$2" == "-u" ]]; then
		#Yes, I know this gives a warning and does not work. I'm assuming there's a reason for that warning,
		#and not implementing a workaround because I'm also assuming that the reason is a good one. Rather
		#than not implementing this feature at all, I'm including the command that should work instead to
		#show users that it's not a good idea to update the username. This option is not in the help text
		#and should be considered deprecated; it is included only for legacy purposes.
		wpcli user update "$1" --user_login="$3" 
	elif [[ "$2" == "-p" ]]; then
		wpcli user update "$1" --user_pass="$3" 
	elif [[ "$2" == "-a" ]]; then
		wpcli user add-role "$1" administrator 
	elif [[ "$2" == "-d" ]]; then
		if [[ -n "$3" ]]; then
			wpcli user delete "$1" --reassign="$3" 
		else
			wpcli user delete "$1"
		fi
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
	elif [[ -z "$2" ]]; then
		wpcli user get "$1"
	else
		wpcli user "$@"
	fi
}

wpplug()
{
	wpenv

	if [[ -z "$1" ]]; then
		echo
		wpcli plugin status
		echo
	elif [[ "$1" == "--help" || "$1" =~ ^-[hH]$ ]] || [[ "$1" == "help" && -z "$2" ]]; then
		echo "
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
	elif [[ "$1" == "help" && -n "$2" ]]; then
		wpcli help user "$@"
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
		wpcli plugin "$@"
	fi
}

wphelp()
{
  echo "
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
