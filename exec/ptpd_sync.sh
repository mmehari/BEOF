#!/bin/bash

# This is a PTPd synchronization program which sends reset commands to a PTPd client
# everytime Offset From Master (OFM) exceeds the maximum value.

PTPd_logFile=$1
OFM_MAX=$2

tail -f $PTPd_logFile | while read line;
do
	# Read client state
	state=$(echo $line | cut -d, -f 2 | xargs)

	if [[ "$state" == "slv" ]]; then

		# Read time Offset From Master (OFM) in seconds
		OFM=$(echo $line | cut -d, -f 5 | xargs)

		# Calculate absolute value of OFM
		OFM=$(echo "sqrt($OFM*$OFM)" | bc -l)

		# If OFM is larger than specified OFM_MAX, reset the clock
		if [[ $(echo "$OFM > $OFM_MAX" | bc -l) == "1" ]]; then
			killall -SIGUSR1 ptpd
		fi
	fi
done
