#!/bin/bash

# Checks if element exists inside array
elementExists()
{
	local element=$1
	local elements=$2[@]
	local array=(${!elements})
	for i in ${array[@]} ; do
		if [ $i == $element ] ; then
			return 0
		fi
	done
	return 1
}

# Search Array elements and display its index
arrayIndex()
{
	local element=$1
	local elements=$2[@]
	local array=(${!elements})
	local Idx=-1
	for (( i = 0; i < ${#array[@]}; i++ )); do
		if [ ${array[$i]} == $element ]; then
			Idx=$i
			break
		fi
	done
	echo $Idx
}

# Insert log message in XML format
insertXML_log()
{
	local type=$1

	if [[ "$type" == "START_MSG" ]]; then
		local id=$2
		local from="EC"
		local to=$3
		local at="`date +%s.%N`"
		local cmd=$4
		local mode=$5

		echo "<START_MSG id=\"$id\" from=\"$from\" to=\"$to\" at=\"$at\" cmd=\"$cmd\" mode=\"$mode\" />" >> $EC_LOG_FILE

	elif [[ "$type" == "END_MSG" ]]; then
		local id=$2
		local from=$3
		local at="`date +%s.%N`"

		echo "<END_MSG id=\"$id\" from=\"$from\" at=\"$at\" />" >> $EC_LOG_FILE

	elif [[ "$type" == "ERROR_MSG" ]]; then
		local id=$2
		local at="`date +%s.%N`"
		local msg=$3

		echo "<ERROR_MSG id=\"$id\" at=\"$at\" msg=\"$msg\" />" >> $EC_LOG_FILE
	fi
}

# Start Resource Controller
startRC()
{
	local HOST_RC=$1

	# Check inside every group for HOST_RC and create unique multicast groups for each occurence
	MCT_ADDR_ARRAY=()
	for GROUP in ${GROUP_ALL[NAME]//,/ }; do
		CTRL_IP_str=$(eval echo \${GROUP_$GROUP[CTRL_IP]})
		MCT_ADDR=$(eval echo \${GROUP_$GROUP[MCT_ADDR]})
		CTRL_IP=(${CTRL_IP_str//,/ })

		if $(elementExists $HOST_RC CTRL_IP) ; then
			MCT_ADDR_ARRAY+=($MCT_ADDR)
		fi
	done
	# Every node is part of GROUP_ALL
	MCT_ADDR_ARRAY+=(${GROUP_ALL[MCT_ADDR]})

	# Join array elements using comma separator
	MCT_ADDR_JOIN=$(IFS=, eval echo '"${MCT_ADDR_ARRAY[*]}"')

	# Start a resource controller instance on the client
	result=( $($EC_EXEC -c -n $HOST_EC -p $PORT_EC -m $HOST_RC -q $PORT_RC_CONNECT -x "0:$HOST_RC $PORT_RC ${OEMV_DIR}/${EXPR_ID}@$HOST_RC.log $MCT_ADDR_JOIN" -r $HOST_RC -t $EC_RECV_SOCK_TIMEOUT | cut -d# -f2-) )

	# Does the connection succedded?
	if [[ "${result[0]}" == "$HOST_RC" && "${result[1]}" == "$PORT_RC" && "${result[2]}" == "${OEMV_DIR}/${EXPR_ID}@$HOST_RC.log" && "${result[3]}" == "$MCT_ADDR_JOIN" ]]; then
		return 0
	fi

	return 1
}

# Excecute command with out result
exec_WOR()
{
	# If argument count equals 2
	if [[ $# -eq 2 ]]; then

		local HOST_RC=$1
		# Escape $ character from command string
		local cmd_exec=$(echo $2 | sed -e 's/\$/\\$/g')
		# Escape special XML characters (i.e. \\r, >, <, & and ") from command string
		local cmd_log=$(echo $2 | sed -e 's/\r/\\n/g' -e 's/>/\&gt;/g' -e 's/</\&lt;/g' -e 's/\&/\&amp;/g' -e 's/\"/\&quot;/g')

		# Retrieve the current SMR
		local SMR=( $(cat $SMR_FILE) )
		local SEQ_NO=${SMR[0]}
		local RC_SENT_MSGs=${SMR[1]}
		local RC_EXPD_RESULTs=${SMR[2]}

		# Increase sequence number
		SEQ_NO=$(($SEQ_NO + 1))

		if $VERBOSE; then				# If verbose mode is enabled
			echo "$SEQ_NO: $2"			# display [sequence #: command]
		fi

		# Total messages counter
		# Unicast message to a single node
		if [ -z "${GNA_COUNT[$HOST_RC]}" ]; then
			RC_SENT_MSGs=$(echo "$RC_SENT_MSGs + 1" | bc)
		# Multicast message to other GROUPs
		else
			RC_SENT_MSGs=$(echo "$RC_SENT_MSGs + $(echo ${GNA_COUNT[$HOST_RC]} | cut -d# -f2)" | bc)
		fi

		# Try locking the SMR file for at most 1sec
		exec 200>/var/lock/SMR_LOCK
		flock -w 1 200

		# Save modified Sequence number, RC sent messages and RC expected Results (SMR) to a file
		echo "$SEQ_NO $RC_SENT_MSGs $RC_EXPD_RESULTs" > $SMR_FILE

		# Release the lock from the SMR file
		flock -u 200

		# Log start of query message
		insertXML_log "START_MSG" "$SEQ_NO" "$HOST_RC" "$cmd_log" "WOR"

		# Execute command
		$EC_EXEC -n $HOST_EC -p $PORT_EC -m $HOST_RC -q $PORT_RC -X "$SEQ_NO:$cmd_exec"

	# Else, put error message
	else
		insertXML_log "ERROR_MSG" "$SEQ_NO" "Argument count mismatch. HOST_RC=$HOST_RC and cmd=$cmd_log"
	fi
}

# Excecute command with result
exec_WR()
{
	# If argument count equals 2
	if [[ $# -eq 2 ]]; then

		local HOST_RC=$1
		# Escape $ character from command string
		local cmd_exec=$(echo $2 | sed -e 's/\$/\\$/g')
		# Escape special XML characters (i.e. \\r, >, <, & and ") from command string
		local cmd_log=$(echo $2 | sed -e 's/\r/\\n/g' -e 's/>/\&gt;/g' -e 's/</\&lt;/g' -e 's/\&/\&amp;/g' -e 's/\"/\&quot;/g')

		# Retrieve the current SMR
		local SMR=( $(cat $SMR_FILE) )
		local SEQ_NO=${SMR[0]}
		local RC_SENT_MSGs=${SMR[1]}
		local RC_EXPD_RESULTs=${SMR[2]}

		# Increase sequence number
		SEQ_NO=$(($SEQ_NO + 1))

		# Multicast message to GROUP_ALL
		if [[ $HOST_RC == ${GROUP_ALL[MCT_ADDR]} ]]; then
			# Total messages counter
			RC_SENT_MSGs=$(echo "$RC_SENT_MSGs + $(echo ${GNA_COUNT[$HOST_RC]} | cut -d# -f2)" | bc)

			# Total expected result counter
			RC_EXPD_RESULTs=$(echo "$RC_EXPD_RESULTs + $(echo ${GNA_COUNT[$HOST_RC]} | cut -d# -f2)" | bc)

			# result is expected from all nodes
			result_IPs=$(echo ${GROUP_ALL[CTRL_IP]} | tr ',' '\n' | sort -u | xargs | sed "s# #,#g")

		# Unicast message to a single node
		elif [ -z "${GNA_COUNT[$HOST_RC]}" ]; then
			# Total messages counter
			RC_SENT_MSGs=$(echo "$RC_SENT_MSGs + 1" | bc)

			# Total expected result counter
			RC_EXPD_RESULTs=$(echo "$RC_EXPD_RESULTs + 1" | bc)

			# result is expected from single node
			result_IPs=$HOST_RC

		# Multicast message to other GROUPs
		else
			# Total messages counter
			RC_SENT_MSGs=$(echo "$RC_SENT_MSGs + $(echo ${GNA_COUNT[$HOST_RC]} | cut -d# -f2)" | bc)

			# Total expected result counter
			RC_EXPD_RESULTs=$(echo "$RC_EXPD_RESULTs + $(echo ${GNA_COUNT[$HOST_RC]} | cut -d# -f2)" | bc)

			# result is expected from multiple nodes
			GROUP=$(echo ${GNA_COUNT[$HOST_RC]} | cut -d# -f1)
			result_IPs=$(eval echo \${GROUP_$GROUP[CTRL_IP]})
		fi

		# Try locking the SMR file for at most 1sec
		exec 200>/var/lock/SMR_LOCK
		flock -w 1 200

		# Save modified Sequence number, RC Messages and RC expected Results (SMR) to a file
		echo "$SEQ_NO $RC_SENT_MSGs $RC_EXPD_RESULTs" > $SMR_FILE

		# Release the lock from the SMR file
		flock -u 200

		insertXML_log "START_MSG" "$SEQ_NO" "$HOST_RC" "$cmd_log" "WR"
		# Execute command
		$EC_EXEC -n $HOST_EC -p $PORT_EC -m $HOST_RC -q $PORT_RC -x "$SEQ_NO:$cmd_exec" -r $result_IPs -t $EC_RECV_SOCK_TIMEOUT | while read line;
		do
			# If message is End Of Result (EOR)
			if [[ $(echo $line | cut -d# -f2-) == "EOR" ]] ; then
				insertXML_log "END_MSG" "$SEQ_NO" "$(echo $line | cut -d# -f1)"
			# If message is Unexpected Result from RC (URRC)
			elif [[ $(echo $line | cut -d# -f2-) == "URRC" ]] ; then
				insertXML_log "ERROR_MSG" "$SEQ_NO" "Unexpected Result from RC $(echo $line | cut -d# -f 1)"
			# If message is Expected Result from RC (ERRC)
			else
				echo $line;
			fi;
		done
	# Else, put error message
	else
		insertXML_log "ERROR_MSG" "$SEQ_NO" "Argument count mismatch. HOST_RC=$HOST_RC and cmd=$cmd_log"
	fi
}

# Retrieve a physical interface name for a given logical Wi-Fi interface
# Assumption: logical interface is already created
RETRV_PHY_IF()
{
	local CTRL_IP=$1
	local LOG_IF=$2
	local i

	# Retrieve all logical interfaces
	LOG_IFs=( $(exec_WR $CTRL_IP "find /sys/class/ieee80211/phy*/device/net -maxdepth 1 -mindepth 1" | cut -d/ -f 8) )
	# Look for matching Logical interface
	for (( i = 0 ; i < ${#LOG_IFs[@]} ; i++ )) do
		if [[ ${LOG_IFs[$i]} == ${LOG_IF} ]]; then
			PHY_IF=$(exec_WR $CTRL_IP "cat /sys/class/net/${LOG_IFs[$i]}/phy80211/name" | cut -d# -f 2)
			echo $PHY_IF
			return 1
		fi
	done

	echo "Could not retrieve physical interface name"
	return 0
}

# Search a matching physical interface for a given logical Wi-Fi interface
# Assumption: logical interface is not yet created
MATCH_LOG_IF_to_PHY_IF()
{
	local CTRL_IP=$1
	local LOG_IF=$2
	local i

	# Retrieve all logical interfaces
	LOG_IFs=( $(exec_WR $CTRL_IP "find /sys/class/ieee80211/phy*/device/net -maxdepth 1 -mindepth 1" | cut -d/ -f 8) )
	# Look for matching Logical interface
	for (( i = 0 ; i < ${#LOG_IFs[@]} ; i++ )) do
		if [[ ${LOG_IFs[$i]} == ${LOG_IF} ]]; then
			PHY_IF=$(exec_WR $CTRL_IP "cat /sys/class/net/${LOG_IFs[$i]}/phy80211/name" | cut -d# -f 2)
			echo $PHY_IF
			return 1
		fi
	done

	# If no matching interface is found, then look for matching index
	for (( i = 0 ; i < ${#LOG_IFs[@]} ; i++ )) do
		if [[ ${LOG_IFs[$i]:${#LOG_IFs[$i]}-1:1} == ${LOG_IF:${#LOG_IF}-1:1} ]]; then
			PHY_IF=$(exec_WR $CTRL_IP "cat /sys/class/net/${LOG_IFs[$i]}/phy80211/name" | cut -d# -f 2)
			echo $PHY_IF
			return 1
		fi
	done

	# Retrieve all physial Wi-Fi interfaces
	PHY_IFs=( $(exec_WR $CTRL_IP "ls /sys/class/ieee80211/" | cut -d# -f 2-) )
	if [[ ${#PHY_IFs[@]} -gt 0 ]]; then
		# If no matching interface index is found, look for matching physical interface index
		for (( i = 0 ; i < ${#PHY_IFs[@]} ; i++ )) do
			if [[ ${PHY_IFs[$i]:${#PHY_IFs[$i]}-1:1} == ${LOG_IF:${#LOG_IF}-1:1} ]]; then
				echo ${PHY_IFs[$i]}
				return 1
			fi
		done

		# If no physical interface is found so far, pick the first one
		echo ${PHY_IFs[0]}
		return 1
	else
		echo "No physical wireless interface exists in the system"
		return 0
	fi
}

# This function converts Wi-Fi channel in the ISM 2.4/5GHz band to frequency representation in MHz
channel_to_freq()
{
   case $1 in
	1)	echo "2412" ;;	2)	echo "2417" ;;	3)	echo "2422" ;;	4)	echo "2427" ;;
	5)	echo "2432" ;;	6)	echo "2437" ;;	7)	echo "2442" ;;	8)	echo "2447" ;;
	9)	echo "2452" ;;	10)	echo "2457" ;;	11)	echo "2462" ;;	12)	echo "2467" ;;
	13)	echo "2472" ;;	14)	echo "2484" ;;	36)	echo "5180" ;;	40)	echo "5200" ;;
	44)	echo "5220" ;;	48)	echo "5240" ;;	52)	echo "5260" ;;	56)	echo "5280" ;;
	60)	echo "5300" ;;	64)	echo "5320" ;;	100)	echo "5500" ;;	104)	echo "5520" ;;
	108)	echo "5540" ;;	112)	echo "5560" ;;	116)	echo "5580" ;;	120)	echo "5600" ;;
	124)	echo "5620" ;;	128)	echo "5640" ;;	132)	echo "5660" ;;	136)	echo "5680" ;;
	140)	echo "5700" ;;	149)	echo "5745" ;;	153)	echo "5765" ;;	157)	echo "5785" ;;
	161)	echo "5805" ;;	165)	echo "5825" ;;
   esac
}

# This function converts Wi-Fi frequency in MHz to channel representation in the ISM 2.4/5GHz band 
freq_to_channel()
{
   case $1 in
	2412)	echo "1" ;;	2417)	echo "2" ;;	2422)	echo "3" ;;	2427)	echo "4" ;;
	2432)	echo "5" ;;	2437)	echo "6" ;;	2442)	echo "7" ;;	2447)	echo "8" ;;
	2452)	echo "9" ;;	2457)	echo "10" ;;	2462)	echo "11" ;;	2467)	echo "12" ;;
	2472)	echo "13" ;;	2484)	echo "14" ;;	5180)	echo "36" ;;	5200)	echo "40" ;;
	5220)	echo "44" ;;	5240)	echo "48" ;;	5260)	echo "52" ;;	5280)	echo "56" ;;
	5300)	echo "60" ;;	5320)	echo "64" ;;	5500)	echo "100" ;;	5520)	echo "104" ;;
	5540)	echo "108" ;;	5560)	echo "112" ;;	5580)	echo "116" ;;	5600)	echo "120" ;;
	5620)	echo "124" ;;	5640)	echo "128" ;;	5660)	echo "132" ;;	5680)	echo "136" ;;
	5700)	echo "140" ;;	5745)	echo "149" ;;	5765)	echo "153" ;;	5785)	echo "157" ;;
	5805)	echo "161" ;;	5825)	echo "165" ;;
   esac
}

# [SIGHUP, SIGINT, SIGQUIT, SIGABRT, SIGKILL] handler
cleanup()
{
	sleep 0.05
	printf "\nSignal recieved from user. Cleaning up resources.\n"

	# User section cleanup
	if [ "`type -t sig_handler`" = 'function' ]; then
		sig_handler
	fi

	# Kill all PAN connections
	if [[ ${#GROUP_ALL_BT[@]} -gt 0 ]]; then
		exec_WOR ${GROUP_ALL_BT[MCT_ADDR]} "pand --killall"
		sleep 0.05
	fi
	# stop GN pand process
	if [[ ${#GROUP_ALL_GN[@]} -gt 0 ]]; then
		exec_WOR ${GROUP_ALL_GN[MCT_ADDR]} "killall -q pand"
		sleep 0.05
	fi
	# stop wpa_supplicant application
	if [[ ${#GROUP_ALL_CLIENT[@]} -gt 0 ]]; then
		exec_WOR ${GROUP_ALL_CLIENT[MCT_ADDR]} "killall -q wpa_supplicant"
		sleep 0.05
	fi
	# stop hostapd application
	if [[ ${#GROUP_ALL_AP[@]} -gt 0 ]]; then
		exec_WOR ${GROUP_ALL_AP[MCT_ADDR]} "killall -q hostapd"
		sleep 0.05
	fi
	# Start udev to execute interface naming events
	if [[ ${#GROUP_ALL_WIFI[@]} -gt 0 ]]; then
		exec_WOR ${GROUP_ALL_WIFI[MCT_ADDR]} "udevadm control --start-exec-queue"
		sleep 0.05
	fi

	# If SYNC_CLOCKS is enabled, stop ptpd from RCs and EC
	if $SYNC_CLOCKS ; then
		sudo killall -q ptpd
		exec_WOR ${GROUP_ALL[MCT_ADDR]} "killall -q ptpd && killall -q tail"
		sleep 0.05
	fi

	# Remove all Resource Controller instances
	echo -e "${Orange}INFO${NC}: RC removal has started ..."
	exec_WR ${GROUP_ALL[MCT_ADDR]} "EXIT"
	echo -e "${Orange}INFO${NC}: RC removed from all nodes"

	echo -e ""
	echo -e "${LCyan}--- Experiment FINISHED ---${NC}"
	echo -e ""
	echo "Expr_ID:    $EXPR_ID"
	# Check if GRAPH and OEMV pages exist
	if which curl > /dev/null
	then
		if curl --output /dev/null --silent --head --fail "$GRAPH_path"; then
			echo "Graph_Path: $GRAPH_path?logFile_path=$TMP_DIR/GRAPH&graphID=$EXPR_ID [UP]"
		else
			echo "Graph_Path: $GRAPH_path?logFile_path=$TMP_DIR/GRAPH&graphID=$EXPR_ID [DOWN]"
		fi

		if curl --output /dev/null --silent --head --fail "$OEMV_path"; then
			echo "OEMV_path:  $OEMV_path?logFile_path=$TMP_DIR/OEMV&exprID=$EXPR_ID [UP]"
		else
			echo "OEMV_path:  $OEMV_path?logFile_path=$TMP_DIR/OEMV&exprID=$EXPR_ID [DOWN]"
		fi
	else
		echo "Graph_Path: $GRAPH_path?logFile_path=$TMP_DIR/GRAPH&graphID=$EXPR_ID [UNKNOWN]"
		echo "OEMV_path:  $OEMV_path?logFile_path=$TMP_DIR/OEMV&exprID=$EXPR_ID [UNKNOWN]"
	fi

	# Orchestration and Error Message (OEM) report

	# Sent messages and expected results
	SMR=( $(cat $SMR_FILE) )
	RC_SENT_MSGs=${SMR[1]}
	RC_EXPD_RESULTs=${SMR[2]}

	# Received results
	RC_RECVD_RESULTs=$(grep -c '<END_MSG ' $EC_LOG_FILE)

	# Recieved messages and execution errors
	RC_RECVD_MSGs=0
	EXEC_ERRORs=0
	HOSTs_ALL=($(printf "%s\n" ${GROUP_ALL[CTRL_IP]//,/ } | sort -u))
	for (( i = 0 ; i < ${#HOSTs_ALL[@]} ; i++ )) do
		RC_RECVD_MSGs=$(echo "$RC_RECVD_MSGs + $(grep -c '<END_MSG '   ${OEMV_DIR}/${EXPR_ID}@${HOSTs_ALL[$i]}.log)" | bc)
		EXEC_ERRORs=$(echo   "$EXEC_ERRORs   + $(grep -c '<ERROR_MSG ' ${OEMV_DIR}/${EXPR_ID}@${HOSTs_ALL[$i]}.log)" | bc)
	done

	printf "\n"
	printf "SENT Messages: %u	LOST Messages: %u\n"	$RC_SENT_MSGs		$(echo "$RC_SENT_MSGs - $RC_RECVD_MSGs" | bc)
	printf "EXPD Results:  %u	LOST Results:  %u\n"	$RC_EXPD_RESULTs	$(echo "$RC_EXPD_RESULTs - $RC_RECVD_RESULTs" | bc)
	printf "EXEC ERRORs:   %u\n"				$EXEC_ERRORs

	exit
}

