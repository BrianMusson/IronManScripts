#!/bin/bash
# Stop docker containers at random


# Ansible environment file
envfile=./inventory

# Temporary file space for IPC (will also create $varfile"_2")
varfile=/tmp/space

# Time to wait between stop/start operations for restart_docker
stop_duration=90

# Time between container/host election
election_duration=10

# Maximum stopped containers
metadata_maxstop=2
haproxy_maxstop=2
vault_maxstop=0
sproxyd_maxstop=2
loggers_maxstop=0
s3_maxstop=2

# You shoudn't need to modify anything below this line

# Verify we have an input inventory file
[[ -f $envfile ]] || (echo "Could not open $envfile. Please check the path and try again."; exit 1)

# Cleanup old var file
[[ -f $varfile ]] || echo > "$varfile" > "$varfile"_2


# Trap control-C so we can clean up our files
trap ctrl_c INT

ctrl_c()
{
        echo "*** Cleaning up variables"
        rm -f "$varfile" "$varfile"_2 
        exit 0
}



# Extract IPs from containers listed in $envfile file and store as arrays
declare -a ironman_metadata_list=( $(perl -lane 'if ( /\[runners_metadata\]/../^$/ ) { print $F[0] if $F[0] =~ /^[\d.]+$/ }' < $envfile) )
declare -a haproxy_list=( $(perl -lane 'if ( /\[haproxies\]/../^$/ ) { print $F[0] if $F[0] =~ /^[\d.]+$/ }' < $envfile) )
declare -a ironman_s3_list=( $(perl -lane 'if ( /\[runners_s3\]/../^$/ ) { print $F[0] if $F[0] =~ /^[\d.]+$/ }' < $envfile) )
declare -a vault_list=( $(perl -lane 'if ( /\[runners_vault\]/../^$/ ) { print $F[0] if $F[0] =~ /^[\d.]+$/ }' < $envfile) )
declare -a sproxyd_list=( $(perl -lane 'if ( /\[sproxyd\]/../^$/ ) { print $F[0] if $F[0] =~ /^[\d.]+$/ }' < $envfile) )
declare -a loggers_list=( $(perl -lane 'if ( /\[loggers\]/../^$/ ) { print $F[0] if $F[0] =~ /^[\d.]+$/ }' < $envfile) )

# Initiate docker container on remote host
# Usage: start_docker <ip> <container>
# Example: start_docker 10.11.12.13 sproxyd
start_docker()
{
	local ipaddress="$1"
	local container="$2"

	dec_var "global" "$container" && dec_var "local" "$container" "$ipaddress"

    echo "ssh root@$ipaddress docker start $container-$ipaddress"

}

# Stop docker container on remote host
# Usage: stop_docker <ip> <container>
# Example: stop_docker 10.11.12.13 sproxyd
stop_docker()
{
	local ipaddress="$1"
	local container="$2"

	inc_var "global" "$container" && inc_var "local" "$container" "$ipaddress"

	echo "ssh root@$ipaddress docker stop $container-$ipaddress"
}

# Restart a docker container on remote host after a sleep duration
# This function backgrounds stop, sleep and start operation
# Usage: restart_docker <ip> <container> <duration>
# Example: restart_docker 10.11.12.13 sproxyd 60
restart_docker()
{
	# Make it easier to read
	local ipaddress="$1"
	local container="$2"
	local duration="$3"

	( stop_docker "$ipaddress" "$container" && sleep "$stop_duration" && start_docker "$ipaddress" "$container" ) & 
}

# Increases variable values
# Usage: inc_var global <container>
# Example: inc_var global sproxyd
# Usage: inc_var local <container> <ipaddress>
# Example: inc_var local sproxyd 10.11.12.13
inc_var()
{
	local varscope="$1"
	local container="$2"
	local ipaddress="$3"

	# If the variable doesn't exist, create it and set it to zero.
	# Otherwise set $var to its value from the file and operate
	if [[ "$varscope" == "global" ]]; then
  		local var=$(grep "$varscope:$container:" "$varfile")
		[[ -z "$var" ]] && echo "$varscope:$container:0" >> "$varfile" 
		awk -F':' '/^'$varscope':'$container'/ {$3+=1;}1' OFS=':' "$varfile" > "$varfile"_2 ; mv "$varfile"{_2,}
    elif [[ "$varscope" == "local" ]]; then
    	local var=$(grep "$varscope:$container:$ipaddress" "$varfile")
		[[ -z "$var" ]] && echo "$varscope:$container:$ipaddress:0" >> "$varfile" 
		awk -F':' '/^'$varscope':'$container':'$ipaddress'/ {$4+=1;}1' OFS=':' "$varfile" > "$varfile"_2 ; mv "$varfile"{_2,}
	fi
}

# Decreases variable values
# Usage: dec_var global <container>
# Example: dec_var global sproxyd
# Usage: dec_var local <container> <ipaddress>
# Example: dec_var local sproxyd 10.11.12.13
dec_var()
{
	local varscope="$1"
	local container="$2"
	local ipaddress="$3"

	# If the variable doesn't exist, create it and set it to zero.
	# Otherwise set $var to its value from the file and operate
	if [[ "$varscope" == "global" ]]; then
  		local var=$(grep "$varscope:$container:" "$varfile")
		[[ -z "$var" ]] && echo "$varscope:$container:0" >> "$varfile" 
		awk -F':' '/^'$varscope':'$container'/ {$3-=1;}1' OFS=':' "$varfile" > "$varfile"_2; mv "$varfile"{_2,}
    elif [[ "$varscope" == "local" ]]; then
    	local var=$(grep "$varscope:$container:$ipaddress" "$varfile")
		[[ -z "$var" ]] && echo "$varscope:$container:$ipaddress:0" >> "$varfile" 
		awk -F':' '/^'$varscope':'$container':'$ipaddress'/ {$4-=1;}1' OFS=':' "$varfile" > "$varfile"_2; mv "$varfile"{_2,}
	fi

}


# Random container selection for restart
# Usage: container_random
# Returns a random container name
container_random()
{
	# Number generator
	local random_number=$[($RANDOM % 5) + 1]
	
	# Container selection
	case "$random_number" in

		1) local container_selection="ironman-metadata" ;;
		2) local container_selection="sproxyd" ;;
		3) local container_selection="haproxy" ;;
		4) local container_selection="vault" ;;
		5) local container_selection="ironman-s3" ;;

	esac

	# Get the count from the last field.
	local gvar=$(grep "global:$container_selection:" "$varfile" | cut -f 3 -d ':')
	[[ -z "$gvar" ]] && local gvar=0	
	# Container selection. If we hit the max, dont provide a result.
	# The "Main loop" will keep retrying until it finds a suitable container
	case "$container_selection" in

		"ironman-metadata") [ "$gvar" -ge "$metadata_maxstop" ] && return ;;
		"haproxy") [ "$gvar" -ge "$haproxy_maxstop" ] && return ;;
		"vault") [ "$gvar" -ge "$vault_maxstop" ] && return ;;
		"sproxyd") [ "$gvar" -ge "$sproxyd_maxstop" ] && return ;;
		"ironman-s3") [ "$gvar" -ge "$s3_maxstop" ] && return ;;
		#"loggers") [ "$gvar" -ge $loggers_maxstop ] && return ;;
	
	esac
	echo "$container_selection"
}

# Random dockerhost based on given $container_name
# Usage: dockerhost_random <$container/$container_random>
# Example: dockerhost_random $container_random

dockerhost_random()
{
	# Load all hosts into an array using the
	local hostlist_array=( "${1//-/_}_list[@]" )
	local hostlist=( "${!hostlist_array}" )
	local hostcount="${#hostlist[@]}"	

    local random_number="$[($RANDOM % $hostcount)]"
    local ipaddress="${hostlist[$random_number]}"
    
    echo "$ipaddress"
	
}

# Main loop
while True; do
	
	unset -v container ipaddress i
	
	# Loop until we find a random container
	while [[ -z "$container" ]]; do
		container="$(container_random)"
	done
    
    # Use the container name from above to find an avaialble ip from the list
    while [ -z "$ipaddress" ]; do
    	ipaddress=$(dockerhost_random "$container")
    	[[ $(grep "local:$container:$ipaddress:1" "$varfile") ]] && unset -v ipaddress && break
	done
	
	[[ "$container" ]] && [[ "$ipaddress" ]] && restart_docker "$ipaddress" "$container" "$stop_duration" 

	# Number of seconds between selection process
	sleep "$election_duration"s

done

