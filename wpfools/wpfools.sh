#!/bin/bash

###
# 
# This code: https://github.com/compilingEntropy/random-scripts/blob/master/wpfools/wpfools.sh
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












wpfix() {
	echo
	if [[ $1 == "--help" || $1 == "-h" ]]; then
		echo -e "This tool runs various built-in Wordpress functions and fixes.\n\nUsage:\n\n\twpfix\n"
		return
	elif [[ ! -f wp-config.php || ! -f wp-admin/upgrade-functions.php ]]; then
		echo -e "Could not find one or more of the necessary files (wp-config.php or wp-admin/upgrade-functions.php)!\n"
		return 9
	fi 
	php -q <<"EOF" && echo "Ran fix..." || echo Error running fix!
<?php
	require_once('wp-config.php');
	echo "WordPress loaded...\n";
	require_once('wp-admin/upgrade-functions.php');
	echo "Upgrade functions loaded...\n";
	wp_cache_flush();
	echo "Object cache flushed...\n";
	make_db_current();
	echo "Database made current...\n";
	/*upgrade_160();
	echo "Data upgraded...\n";*/
	$wp_rewrite->flush_rules();
	echo "Rewrite rules flushed...\n";
	wp_cache_flush();
	echo "Object cache flushed...\n";
?>
EOF
	echo
}

wpht() {
	echo
	if [[ $1 == "--help" || $1 == "-h" ]]; then
		echo -e "This tool generates a new .htaccess file.\n\nUsage:\n\n\twpht\n"
		return
	elif [[ ! -f wp-config.php || ! -f wp-admin/includes/misc.php ]]; then
		echo -e "Could not find one or more of the necessary files:\n"
		echo -e "\twp-config.php\n\twp-admin/includes/misc.php\n"
		return 9
	fi
	temp=$(now)
	[[ -f .htaccess ]] && cp .htaccess .htaccess_$temp
	php -q <<"EOF" && echo "Generated .htaccess rules..." || echo Error writing to .htaccess!
<?php
	$_SERVER['SCRIPT_NAME'] = "";
	require_once('wp-config.php');
	require_once('wp-admin/includes/misc.php');
	$rules = explode( "\n", $wp_rewrite->mod_rewrite_rules() );
	insert_with_markers( '.htaccess', 'WordPress', $rules );
?>
EOF
	echo
}

wpconn() {
	[[ -z $1 || $1 != wp* ]] && return
	if [[ ! -f wp-config.php ]]; then
		echo -e "\nCould not find wp-config.php!\n"
		return 9
	fi
	myconn=""
	read -r dbhost dbname dbpass dbuser dbprefix <<< $(cat wp-config.php | egrep "^[^/].*[\"']DB_(NAME|USER|PASSWORD|HOST[^_])|table_prefix" | sort -d | sed "s/.*[\"']\(.*\)[\"'].*;.*/\1/" )
	#[[ -z $dbprefix ]] && dbprefix=$junk #sometimes there isn't a junk entry
	q="USE $dbname; "
	if [[ $1 == "wpdbimport" ]]; then
		echo "Starting import..."
		mysql -h "$dbhost" -u "$dbuser" -p"$dbpass" "$dbname" < "$2" && echo -e "Imported file '$2' to database '$dbname'.\n" || echo -e "Failed to import file '$2' to database '$dbname'!\n"
		return
	elif [[ $1 == "wpdbimportgz" ]]; then
		echo "Starting import..."
		gunzip < "$2" | mysql -h "$dbhost" -u "$dbuser" -p"$dbpass" "$dbname" && echo -e "Imported gzipped file '$2' to database '$dbname'.\n" || echo -e "Failed to import file '$2' to database '$dbname'!\n"
		return
	elif [[ $1 == "wpdbexport" ]]; then
		echo "Starting export..."
		file="$2"
		[[ -z "$file" ]] && file="$dbname"_$(now).sql
		mysqldump -h "$dbhost" -u "$dbuser" -p"$dbpass" "$dbname" > "$file" && echo -e "Exported database '$dbname' to file '$file'.\n" || echo -e "Failed to export database '$dbname' to file '$file'!\n"
		return
	elif [[ $1 == "wpdbexportgz" ]]; then
		echo "Starting export..."
		file="$2"
		[[ -z "$file" ]] && file="$dbname"_$(now).sql.gz
		mysqldump -h "$dbhost" -u "$dbuser" -p"$dbpass" "$dbname" | gzip > "$file" && echo -e "Exported gzipped database '$dbname' to file '$file'.\n" || echo -e "Failed to export database '$dbname' to file '$file'!\n"
		return
	elif [[ $1 == "wpdbdrop" ]]; then q='DROP database '$dbname'; CREATE DATABASE '$dbname';';
	elif [[ $1 == "wpdb" ]]; then q=$q'SHOW tables like "'$dbprefix'%";';
	elif [[ $1 == "wpdbver" ]]; then q=$q'SELECT option_value FROM '$dbprefix'options WHERE option_name = "db_version";'
	elif [[ $1 == "wpurl" ]]; then q=$q'SELECT option_id, option_name, option_value FROM '$dbprefix'options WHERE option_name = "siteurl" OR option_name = "home";'
	elif [[ $1 == "wpurlmod" ]]; then
		[[ -z $2 ]] && echo No URL specified! && return 9
		q=$q'UPDATE '$dbprefix'options SET option_value="'$2'" WHERE option_name="siteurl" OR option_name="home";'
	elif [[ $1 == "wpplug" ]]; then q=$q'SELECT option_value FROM '$dbprefix'options WHERE option_name = "active_plugins";'
	elif [[ $1 == "wptheme" ]]; then q=$q'SELECT option_id, option_name, option_value FROM '$dbprefix'options WHERE option_name = "stylesheet" OR option_name = "template";'
	elif [[ $1 == "wpthememod"* ]]; then
		[[ -z $2 ]] && echo No theme specified! && return 9
		if [[ $1 == "wpthememod" ]]; then q=$q'UPDATE '$dbprefix'options SET option_value="'$2'" WHERE option_name="stylesheet" OR option_name="template" OR option_name="current_theme";'
		elif [[ $1 == "wpthememods" ]]; then q=$q'UPDATE '$dbprefix'options SET option_value="'$2'" WHERE option_name="stylesheet";'
		elif [[ $1 == "wpthememodt" ]]; then q=$q'UPDATE '$dbprefix'options SET option_value="'$2'" WHERE option_name="template" OR option_name="current_theme";'
		else echo -e "\tInvalid query"! && return 1
		fi
	elif [[ $1 == "wpuser" ]]; then q=$q'SELECT * FROM '$dbprefix'users LIMIT 23;'
	elif [[ $1 == "wpuser1" ]]; then q=$q'SELECT user_login FROM '$dbprefix'users WHERE ID=1;'
	elif [[ $1 == "wpuserinfo" ]]; then q=$q'SELECT ID, user_login, user_email, user_status, umeta_id, meta_key, meta_value FROM '$dbprefix'users JOIN '$dbprefix'usermeta ON ('$dbprefix'users.ID = '$dbprefix'usermeta.user_id) WHERE ID='$2';'
	elif [[ $1 == "wpusera" ]]; then q=$q'DELETE FROM '$dbprefix'usermeta WHERE user_id='$2' AND (meta_key="'$dbprefix'capabilities" OR meta_key="'$dbprefix'user_level"); INSERT INTO '$dbprefix'usermeta (user_id,meta_key,meta_value) VALUES ('$2', "'$dbprefix'capabilities", '"'a:1:{s:13:\"administrator\";b:1;}'"'); INSERT INTO '$dbprefix'usermeta (user_id,meta_key,meta_value) VALUES ('$2', "'$dbprefix'user_level", 10); SELECT user_login FROM '$dbprefix'users WHERE ID='$2';'
	elif [[ $1 == "wpuserp" ]]; then q=$q'UPDATE '$dbprefix'users SET user_pass=MD5("'$3'") WHERE ID='$2'; SELECT user_login FROM '$dbprefix'users WHERE ID='$2';'
	elif [[ $1 == "wpuseru" ]]; then q=$q'SELECT user_login FROM '$dbprefix'users WHERE ID='$2'; UPDATE '$dbprefix'users SET user_login="'$3'" WHERE ID='$2';'
	elif [[ $1 == "wpuserd" ]]; then q=$q'SELECT user_login FROM '$dbprefix'users WHERE ID='$2'; DELETE FROM '$dbprefix'users WHERE ID='$2'; DELETE FROM '$dbprefix'usermeta WHERE user_id='$2';'
	elif [[ $1 == "wpusernew" ]]; then q=$q'INSERT INTO '$dbprefix'users (user_login, user_pass, user_email) VALUES ("deleteme", MD5("deleteme"), "deleteme@example.com"); SET @new_id=LAST_INSERT_ID(); INSERT INTO '$dbprefix'usermeta (user_id,meta_key,meta_value) VALUES (@new_id, "'$dbprefix'capabilities", '"'a:1:{s:13:\"administrator\";b:1;}'"'); INSERT INTO '$dbprefix'usermeta (user_id,meta_key,meta_value) VALUES (@new_id, "'$dbprefix'user_level", 10); SELECT @new_id;'
	else echo -e "\tInvalid query"! && return 1
	fi
	myconn=$(mysql -u "$dbuser" -p"$dbpass" -h "$dbhost" -e "$q" 2>&1)
	if [[ 1 -eq 0 ]]; then #Debug
		echo -e "\nConnected to the database..."
		echo -e "Query:\n\n\t$q"
		echo -e "$myconn".
	elif [[ $myconn == "ERROR"* ]]; then return 9
	fi
}

wpdb() {
	#Need to include a optimize/fix option
	if [[ $1 == "--help" || $1 == "-h" ]]; then
		echo -e "\nThis tool tests the database connectivity based on settings in the wp-config.php file, and can import/export a database based on its settings.\n"
		echo -e "Usage:\n"
		echo -e "\twpdb [option [param]]\n"
		echo -e "\t-i FILE\n\t\texport current database to file FILE. The specified FILE must end in .sql"
		echo -e "\t-e [FILE]\n\t\texport current database to optional file FILE. If a FILE is specified, it must end in .sql\n"
		return
	elif [[ ! -f wp-config.php ]]; then echo Could not find wp-config.php! && return 9
	fi
	wpconn "wpdb"
	[[ $1 != "-q" ]] && echo -e "\n\tDB user:\t$dbuser\n\tDB pass:\t$dbpass\n\tDB host:\t$dbhost\n\tDB name:\t$dbname\n\tDB prefix:\t$dbprefix\n"
	if [[ -z $myconn ]]; then
		[[ $1 == "-q" ]] && echo -e "\tDatabase:\tPrefix?" || echo -e "Connected with no errors, but no tables that match specified prefix"!"\n"
	elif [[ $myconn == "ERROR"* ]]; then
		[[ $1 == "-q" ]] && echo -e "\tDatabase:\tError"! || echo -e "$myconn\n"
		return 9
	else
		[[ $1 == "-q" ]] && echo -e "\tDatabase:\tOK" || echo -e "Database connection settings appear to be fine.\n"
	fi
	if [[ $1 == "-i" ]]; then
		if [[ -z "$2" ]]; then echo -e "No import file specified!\n"
		elif [[ ! -f "$2" ]]; then echo -e "File '$2' does not exist!\n"
		elif [[ "$2" == *sql ]]; then wpconn "wpdbimport" "$2"
		elif [[ "$2" == *sql.gz ]]; then wpconn "wpdbimportgz" "$2"
		else echo -e "'$2' is not a valid file!\n"
		fi
	elif [[ $1 == "-e" ]]; then
		if [[ -n "$2" ]]; then
			if [[ -f "$2" ]]; then echo -e "File '$2' already exists!\n"
			elif [[ "$2" == *sql ]]; then wpconn "wpdbexport" "$2"
			elif [[ "$2" == *sql.gz ]]; then wpconn "wpdbexportgz" "$2"
			else echo -e "'$2' is not a valid filename!\n" && return
			fi
		else
			wpconn "wpdbexport"
		fi
	elif [[ $1 == "drop" ]]; then
		read -p "$(echo $'\t')Delete database? " -n 1 -r
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			echo -e "\nDropping database..."
			wpconn "wpdbdrop"
			[[ $myconn != "ERROR"* ]] && echo -e "Dropped database!\n" || echo -e "Failed to drop database!\n"
		else echo -e "\tDeletion of database '$1' cancelled"!"\n"
		fi
	fi
}

wpurl() {
	[[ $1 == "-q" ]] && wpconn "wpurl" && echo "$myconn" | tail -n +2 && return
	echo
	if [[ $1 == "--help" || $1 == "-h" ]]; then
		echo -e "This tool returns the current URL settings in the database, or updates them to a specified URL.\n"
		echo -e "Usage:\n"
		echo -e "\twpurl [URL]\n"
		echo -e "\tURL\n\t\tspecify a URL to change the site to. If the URL does not start with 'http://' or 'https://' it will automatically append 'http://'.\n"
		return
	elif [[ ! -f wp-config.php ]]; then echo Could not find wp-config.php! && return 9
	fi
	if [[ -n $1 ]]; then
		newurl=$1
		[[ ! $newurl =~ https?://* ]] && newurl="http://"$newurl && echo "No 'http://' or 'https://' in provided URL"! && echo "Using '$newurl' instead..."
		wpconn "wpurlmod" $newurl && echo "Updated URLs to $newurl..."
	else
		wpconn "wpurl"
		[[ -z $myconn ]] && echo -e "\thome:\tnot found\n\tsiteurl:\tnot found\n" && return
		echo -e "$myconn" | tail -n +2 | awk '{print "\t"$2"("$1"):\t"$3}'
	fi
	echo
}

wptheme() {
	[[ $1 != "-q" ]] && echo
	if [[ $1 == "--help" || $1 == "-h" ]]; then
		echo -e "This tool returns the current theme, as well as listing any available ones found in the wp-content/themes folder. It also can change to a specified stylesheet, template, both, or to a new copy of twentytwelve.\n"
		echo -e "Usage:\n"
		echo -e "\twptheme [THEME [option]]\n"
		echo -e "\tTHEME\n\t\tspecify a THEME for both the stylesheet and template. If 'fresh' is specified as the theme, it will download and install the 'twentytwelve' theme."
		echo -e "\tTHEME -s\n\t\tchange only the WP stylesheet"
		echo -e "\tTHEME -t\n\t\tchange only the WP template\n"
		return
	elif [[ ! -f wp-config.php ]]; then echo Could not find wp-config.php! && return 9
	fi
	folder=wp-content/themes
	if [[ $1 == "-q" || -z $1 ]]; then
		wpconn "wptheme"
		if [[ $myconn == "" ]]; then echo -e "\tstylesheet:\tnot found\n\ttemplate:\tnot found"
		elif [[ $myconn != "ERROR"* ]]; then
			echo -e "$myconn" | tail -2 | awk '{print "\t"$2"("$1"):\t"$3}'
		fi
	fi
	[[ ! -d $folder && $1 != "-q" ]] && mkdir -p $folder && echo -e "\nCreated $folder..."
	if [[ $1 == "-q" ]]; then return
	elif [[ -z $1 ]]; then
		echo -e "\nAvailable themes:\n"
		ls -F $folder |grep "/"|grep -v "^\."|sed "s|^\(.*\)/|\t\1|" #ls -A is overwritten by default $LS_OPTIONS in alias
	elif [[ $1 == "fresh" ]]; then
		wget -qP $folder https://wordpress.org/extend/themes/download/twentytwelve.1.1.zip && echo "Downloaded twentytwelve.1.1.zip..." || {
			echo Unable to download twentytwelve.1.1.zip!
			return 9
		}
		temp=$(now)
		[[ -d $folder/twentytwelve ]] && mv $folder/twentytwelve $folder/twentytwelve_$temp && echo "Moved old twentytwelve files to twentytwelve_$temp..."
		unzip $folder/twentytwelve.1.1.zip -d $folder >/dev/null && echo "Extracted new twentytwelve files..." || {
			echo "Failed to extract twentytwelve files"!
			return 1
		}
		wpconn "wpthememod" "twentytwelve" && echo "Changed to theme 'twentytwelve'..."
		rm -f $folder/twentytwelve.1.1.zip && echo "Deleted twentytwelve.1.1.zip..."
	else
		[[ ! -d wp-content/themes/$1 ]] && echo -e "No such theme"!"\n" && return 1
		if [[ $2 == "-s" ]]; then wpconn "wpthememods" $1 && echo "Changed to stylesheet '$1'..."
		elif [[ $2 == "-t" ]]; then wpconn "wpthememodt" $1 && echo "Changed to template '$1'..."
		elif [[ -n $2 ]]; then echo "Invalid option"!
		else wpconn "wpthememod" $1 && echo "Changed to theme '$1'..."; fi
	fi
	echo
}

wpver() {
	if [[ $1 == "--help" || $1 == "-h" ]]; then
		echo -e "
This tool returns the current install's file and database versions.

  Usage:

\twpver [option]

\t    -q\n\t\tdisplay abbreviated version output
\t    -h\n\t\tdisplay this help output
"
		return
	fi
	local filever="Unknown"
	local dbver="Unknown"
	local dbver_files="Unknown"
	[[ -f wp-includes/version.php ]] && filever=$(cat wp-includes/version.php | grep "wp_version " | sed "s/.*'\(.*\)'.*/\1/")
	wpconn "wpdbver"
	if [[ $? == 0 && $myconn != "ERROR"* ]]; then
		dbver=$(echo -e "$myconn" | tail -1)
		dbver_files=$(curl -Ss https://codex.wordpress.org/FAQ_Installation | grep "= $dbver" | head -1 | awk '{print $1}')
	fi
	if [[ "$1" == "-q" ]]; then echo -e "$filever $dbver $dbver_files"
		else echo -e "\n\tWP version:\t$filever\n\tDB version:\t$dbver (up to $dbver_files)\n"
	fi
}

wpuser() {
	[[ $1 != "-q" ]] && echo
	if [[ $1 == "--help" || $1 == "-h" ]]; then
		echo -e "This tool performs various user functions, including returning info for a specified user, changing usernames, passwords, changing a user to an admin, creating new admin users, and deleting users.\n"
		echo -e "Usage:\n"
		echo -e "\twpuser [param [option [param]]]\n"
		echo -e "\tUSERID\n\t\tReturns details about specified user USERID"
		echo -e "\tUSERID -u NAME\n\t\tchange username of user USERID to NAME"
		echo -e "\tUSERID -p PASS\n\t\tchange password of user USERID to PASS"
		echo -e "\tUSERID -a\n\t\tpromote user USERID to admin"
		echo -e "\tUSERID -d\n\t\tdelete user USERID"
		echo -e "\t-n, new\n\t\tcreate new admin user\n"
		return
	elif [[ ! -f wp-config.php ]]; then echo Could not find wp-config.php! && return 9
	fi
	if [[ -z $1 ]]; then wpconn "wpuser"								#list users
	elif [[ $1 == "-q" ]]; then wpconn "wpuser1"						#list first user
	elif [[ $1 =~ ^[0-9]+$ ]]; then								#if a number...
		if [[ $2 == "-p" ]]; then											#change password...
			if [[ -n $3 ]]; then wpconn "wpuserp" $1 "$3"					#...if one is specified...
		else echo -e "\tNo password specified"!"\n" && return 1; fi   #...otherwise, end.
		elif [[ $2 == "-u" ]]; then										  #change username...
			if [[ -n $3 ]]; then wpconn "wpuseru" $1 "$3"					#...if one is specified...
			else echo -e "\tNo username specified"!"\n" && return 1; fi	 #...otherwise, end.
		elif [[ $2 == "-a" ]]; then wpconn "wpusera" $1		 		  #change to admin
		elif [[ $2 == "-d" ]]; then read -p "$(echo $'\t')Delete user '$1'? " -n 1 -r && echo && [[ ! $REPLY =~ ^[Yy]$ ]] && echo -e "\tDeletion of user '$1' cancelled"!"\n" && return 1 || wpconn "wpuserd" $1		 		  #delete user
		elif [[ -z $2 ]]; then wpconn "wpuserinfo" $1				  #show user info
		else echo -e "\tInvalid option"!"\n" && return 1; fi				  #Otherwise, end.
	elif [[ $1 == "new" || $1 == "-n" ]]; then wpconn "wpusernew"				#create new admin...
	else echo -e "\tInvalid option"!"\n" && return 1; fi				#Otherwise, end.
	if [[ $myconn == "" ]]; then echo -e "\tUser not found"!
	elif [[ $myconn != "ERROR"* ]]; then
		if [[ -z $1 ]]; then echo -e "$myconn" | tail -n +2 | awk '{print "\t"$1":\t"$2}'
		elif [[ $1 == "-q" ]]; then echo $(echo -e "$myconn" | tail -1)
		elif [[ $2 == "-p" ]]; then echo -e "Updated password for user $1 ('$(echo -e "$myconn" | tail -1)') to '$3'..."
		elif [[ $2 == "-u" ]]; then echo -e "Updated username for user $1 from '$(echo -e "$myconn" | tail -1)' to '$3'..."
		elif [[ $2 == "-a" ]]; then echo -e "Promoted user $1 to admin..."
		elif [[ $2 == "-d" ]]; then echo -e "\nDeleted user $1 ('$(echo -e "$myconn" | tail -1)')..."
		elif [[ $1 == "new" || $1 == "-n" ]]; then echo -e "Created new admin (user '$(echo -e "$myconn" | tail -1)') with username 'deleteme' and password 'deleteme'...\n\nMake sure to delete or rename this user"!
		elif [[ -z $2 ]]; then echo -e "$myconn" | tail -n +2
		fi
	else echo "$myconn"
	fi
	[[ $1 != "-q" ]] && echo
}

wpplug() {
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

wptests() {
	if [[ $1 == "--help" || $1 == "-h" ]]; then
		echo -e "This tool does basic tests on the install.\n"
		echo -e "Usage:\n"
		echo -e "\twptests [param [option param]]\n"
		echo -e "\tall\n\t\ttests each item in wp-content/plugins on the server\n"
		echo -e "\tall --url URL\n\t\ttests HTTP status code for each item in wp-content/plugins at specified url URL\n"
		return
	elif [[ ! -f wp-config.php ]]; then echo Could not find wp-config.php! && return 9
	fi
	if [[ $2 == "--url" && -n $3 ]]; then status=$(curl -sIL -o /dev/null -w "%{http_code}\n" $3)
	else status=$(php index.php >/dev/null && php wp-admin/index.php >/dev/null; echo $?); fi
	[[ $1 == "-q" ]] && echo $status && return
	echo
	[[ $status != "255" && $status != "500" ]] && echo -e "No errors detected..." || echo -e "500 error on page"!
	echo
	[[ -z $1 ]] && return
	[[ $1 == "all" ]] && folders="wp-content/plugins" || folders=$(echo $1|sed "s|/$||g")
	temp=$(now)
	if [[ $2 == "--url" && -n $3 ]]; then echo -e "*** NOTE: This test doesn't confirm items are fully functional; it simply checks the status code on '$3'. DO NOT INTERRUPT! ***\n"
	else echo -e "*** NOTE: This test doesn't confirm items are fully functional; it simply tries to run index.php and wp-admin/index.php in the local shell. DO NOT INTERRUPT! ***\n"; fi
	temp=$(now)
	for f in $folders; do
		[[ ! -d $f ]] && echo "The folder '$f' was not found"! && continue
		echo "Testing $f..."
		mv $f "$f"_$temp && echo "Moved $f to $f"_$temp...
		mkdir $f && echo "Created new $f folder..."
		status=$(wptests -q --url $3); [[ $status == "255" || $status == "500" ]] && echo "Renaming the $f folder results in a 500 error...errors below MAY be safe to ignore"! || echo "Renaming the $f folder appears to result in no error..."
		for i in "$f"_$temp/*; do
			[[ -f $i ]] && continue
			plugin=${i##*/}
			mv "$f"_$temp/$plugin $f && echo -e "\tTesting ${f%?} '$plugin'..." $(
				status=$(wptests -q --url $3)
				if [[ $status == "200" || $status == "0" ]]; then echo "OK"
				elif [[ $status == 255 ]]; then echo "500"
				else echo $status; fi
			) && mv $f/$plugin "$f"_$temp
		done
		mv "$f"_$temp/* $f && echo "Moved $f back to original folder..." && rm -rf "$f"_$temp && echo "Removed $f"_$temp...
  done
  echo
}

wpstats() {
	if [[ $1 == "--help" || $1 == "-h" ]]; then
		echo -e "\nThis tool returns a basic overview of the Wordpress install.\n\nUsage:\n\n\twpstats\n" && return
	elif [[ -n $1 ]]; then return
	fi
	echo
	echo -e "\tWP version:\t"$(wpver -q | awk '{print $1}')
	echo -e "\tStatus code:\t"$( temp=$(wptests -q); [[ $temp != "255" ]] && echo "OK" || echo "Error"!)
	if wpdb -q; then
		echo -e "\tUserID 1:\t"$(wpuser -q)
		wpurl -q | awk '{print "\t"$2"("$1"):\t"$3}'
		wptheme -q
	fi
	echo
}

wptool() {
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
  
\twpstats: basic overview
\twpurl:   URL tools
\twptheme: theme tools
\twpdb:    db tools
\twpuser:  user tools
\twpplug:  plugin tools
\twpht:    .htaccess generator
\twpcore:  core replacement tools
\twpfix:   built-in WP fixes
\twpver:   returns version info
"
}

#search, multisite
wptoolv="1.7.1.2"
echo -e "\n    Injected WPtool $wptoolv into current session. For details, type 'wptool'.\n"
unset HISTFILE
