#!/bin/bash
# This program pings a given network node and dumps reply statistics to a [mysql] database server

# Trap the following signals (SIGHUP, SIGINT, SIGQUIT, SIGABRT, SIGKILL) and exit the program
cleanup()
{
	exit
}
trap cleanup 1 2 3 6 9

# Parse command line argument
while getopts "n:u:k:d:a:s:ih" opt; do
case "$opt" in
	n) HOST=$OPTARG;;
	u) USER=$OPTARG;;
	k) PASSWD=$OPTARG;;
	d) DB=$OPTARG;;
	a) hostIP=$OPTARG;;
	s) packetsize=$OPTARG;;
	i) INTVAL=$OPTARG;;
	h|*) echo "Description"
	     echo "-----------"
	     echo "ping_wrapper.sh is a wrapper around the ping program, used to automate network connection test and save results into a mysql database."
	     echo ""
	     echo "Argument list"
	     echo "-------------"
	     echo "-n HOST           mysql hostname [-eq -n 127.0.0.1]"
	     echo "-u USER           mysql username [-eq -u root]"
	     echo "-k PASSWD         mysql password [-eq -k root]"
	     echo "-d DB             mysql database [-eq -d benchmarking]"
	     echo "-a hostIP         host IP address [-eq -a 127.0.0.1]"
	     echo "-s packetsize     packet payload size (bytes) [-eq -s 64]"
	     echo "-i INTVAL         measurment interval (usec) [-eq -i 100]"
	     echo ""
	     exit 0 ;;
esac
done

IFS=$'\n'
while :
do
	# Log start time
	start_time=$(date +%s%6N)

	# Ping the host and retrieve result within 1 second timeout
	ping_rlt=$(ping -n -f -c 50 -q -s $packetsize -w 1 $hostIP)

	# If ping result is from stderr, exit the wrapper
	if [[ $? -eq 2 ]]; then

		echo "$ping_rlt" >&2
		exit
	fi

	readarray ping_array < <(echo "$ping_rlt")

	# bash regular expression to host address
	host_regexp="^PING"

	# bash regular expression to detect ping packet loss (pl)
	pl_regexp="^[0-9]+ packets transmitted, [0-9]+ received, [0-9]+% packet loss, time [0-9]+ms"

	# bash regular expression to detect ping round trip time (rtt)
	rtt_regexp="^rtt min/avg/max/mdev = ([0-9]+.[0-9]+)/([0-9]+.[0-9]+)/([0-9]+.[0-9]+)/([0-9]+.[0-9]+) ms"

	# Initial lqi and rtt values
	lqi="0"
	rtt="inf"

	# For each line of the ping result
	for (( i = 0 ; i < ${#ping_array[@]} ; i++ )) do

		# match host IP address
		if   [[ ${ping_array[i]} =~ $host_regexp ]]; then

			hostIP=$(echo ${ping_array[i]} | cut -d'(' -f2 | cut -d')' -f1)

		# match pl
		elif [[ ${ping_array[i]} =~ $pl_regexp  ]]; then

			pl=$(echo ${ping_array[i]} | cut -d' ' -f6)
			lqi=$((100 - ${pl::-1}))

		# match rtt
		elif [[ ${ping_array[i]} =~ $rtt_regexp  ]]; then

			rtt=$(echo ${ping_array[i]} | cut -d= -f2 | cut -d/ -f2)
		fi
	done

	# Insert hostIP and rtt into mysql database
	mysql -h $HOST --user=$USER --password=$PASSWD -Bse "INSERT INTO ping_stat VALUES ($start_time,'$hostIP','$lqi','$rtt')" $DB 2> /dev/null

	# Wait before processing the next data
	current_time=$(date +%s%6N)
	if [[ $((current_time - start_time)) -lt $INTVAL ]]; then
		sleep $(echo "($INTVAL - ($current_time - $start_time))/1000000" | bc -l)
	fi
done
