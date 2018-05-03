#!/bin/bash

# ---------------------- System signal handler ------------------- #
# Trap the following signals: [SIGHUP, SIGINT, SIGQUIT, SIGABRT, SIGKILL]
trap cleanup 1 2 3 6 9


# -------------------- Group to Node Arrangment (GNA) ----------------- #
# Log GNA start tag
GNA_str=$"<GNA>\n"
GNA_str=$"${GNA_str}\t<group name=\"ALL\" addr=\"${GROUP_ALL[MCT_ADDR]}\">\n"

# Save GNA counter to array
declare -A GNA_COUNT=()

# Log GROUP_ALL GNA entry. First remove duplicate entries from ${GROUP_ALL[CTRL_IP]}
HOSTs_ALL=($(printf "%s\n" ${GROUP_ALL[CTRL_IP]//,/ } | sort -u))
for (( i = 0 ; i < ${#HOSTs_ALL[@]} ; i++ )) do
	GNA_str=$"${GNA_str}\t\t<node addr=\"${HOSTs_ALL[$i]}\" />\n"
done
GNA_str=$"${GNA_str}\t</group>\n"
GNA_COUNT[${GROUP_ALL[MCT_ADDR]}]="ALL#${#HOSTs_ALL[@]}"

# For each Group, log and save GNA entries
for GROUP in ${GROUP_ALL[NAME]//,/ }; do

	CTRL_IP_str=$(eval echo \${GROUP_$GROUP[CTRL_IP]})
	MCT_ADDR=$(eval echo \${GROUP_$GROUP[MCT_ADDR]})
	CTRL_IPs=( ${CTRL_IP_str//,/ } )

	GNA_str=$"$GNA_str\t<group name=\"$GROUP\" addr=\"$MCT_ADDR\">\n"
	for (( i = 0 ; i < ${#CTRL_IPs[@]} ; i++ )) do
		GNA_str=$"${GNA_str}\t\t<node addr=\"${CTRL_IPs[$i]}\" />\n"
	done

	GNA_str=$"${GNA_str}\t</group>\n"
	GNA_COUNT[$MCT_ADDR]="$GROUP#${#CTRL_IPs[@]}"
done
# Log GNA end tag
GNA_str=$"${GNA_str}</GNA>"

# save GNA to EC_LOG_FILE
printf "$GNA_str\n" >> $EC_LOG_FILE


# -------------------- Log/GRAPH/OEMV files path ----------------- #
echo ""
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
echo ""


# -------------------------- RC installation -------------------------- #
echo -e "${Orange}INFO${NC}: RC installation has started ...";
# Start Resource Controller. First remove duplicate entries from ${GROUP_ALL[CTRL_IP]}
HOSTs_ALL=($(printf "%s\n" ${GROUP_ALL[CTRL_IP]//,/ } | sort -u))

# declare an array of retry count for all RC nodes during RC installation
declare -a RC_START_RETRIEs_ARRAY=($(eval printf "\"%0.s$RC_START_RETRIES \"" {1..${#HOSTs_ALL[@]}}))
# Array to hold reachable RC nodes
REACHABLE_RCs=()
for (( i = 0 ; i < ${#HOSTs_ALL[@]} ; i++ )) do
	# Start RC program on all nodes
	if startRC ${HOSTs_ALL[$i]}; then
		REACHABLE_RCs+=(${HOSTs_ALL[$i]})
	else
		echo -e "${LRed}ERROR${NC}: EC cannot reach ${HOSTs_ALL[$i]}"
		# Check if RC retry limit is reached
		if [[ ${RC_START_RETRIEs_ARRAY[$i]} == 0 ]]; then
			# If at least one RC node cannot be reached, then try to remove all RCs from previously installed nodes.
			# We assume the startRC call installs the RC program.
			echo -e "${Orange}INFO${NC}: RC removal has started ...";
			for (( j = 0 ; j < ${#REACHABLE_RCs[@]} ; j++ )) do
				exec_WR ${HOSTs_ALL[$i]} "EXIT"
			done
			echo -e "${Orange}INFO${NC}: RC removed from all nodes";
			echo -e ""
			echo -e "${LRed}Experiment Failed${NC}"
			exit
		fi
		RC_START_RETRIEs_ARRAY[$i]=$(echo "${RC_START_RETRIEs_ARRAY[$i]}-1" | bc)
		((i--))
	fi
done

# PING all RC nodes to check if installation is successful
result=( $(exec_WR ${GROUP_ALL[MCT_ADDR]} "PING") )
STARTED_RCs=()
for (( i = 0 ; i < ${#result[@]} ; i++ )) do
	CTRL_IP=$(echo ${result[$i]} | cut -d# -f 1)
	STATUS=$(echo ${result[$i]} | cut -d# -f 2-)

	if [[ "$STATUS" == "PONG" ]]; then
		STARTED_RCs+=($CTRL_IP)
	fi
done

# Once again, iterate through each RC nodes and check if all nodes are started. If not, try restarting.
for (( i = 0 ; i < ${#HOSTs_ALL[@]} ; i++ )) do
	if ! $(elementExists ${HOSTs_ALL[$i]} STARTED_RCs) ; then
		# If PING message was not replied, try re-installing the RC
		echo -e "${LRed}ERROR${NC}: RC instalation on ${HOSTs_ALL[$i]} failed"
		for (( j = 0 ; j < ${RC_START_RETRIEs_ARRAY[$i]} ; j++ )) do
			echo -e "${Orange}INFO${NC}: Installing RC on ${HOSTs_ALL[$i]}. TRIAL $((j+1))"
			if startRC ${HOSTs_ALL[$i]} ; then
				if [[ $(exec_WR ${HOSTs_ALL[$i]} "PING" | cut -d# -f 2-) == "PONG" ]] ; then
					STARTED_RCs+=(${HOSTs_ALL[$i]})
					break
				else
					echo -e "${LRed}ERROR${NC}: Installing RC on ${HOSTs_ALL[$i]} failed"
				fi
			else
				echo -e "${LRed}ERROR${NC}: EC cannot reach ${HOSTs_ALL[$i]}"
			fi
		done
		# If RC's retry limit has expired. Remove all started RCs and stop the experiment.
		if [[ $j -eq ${RC_START_RETRIEs_ARRAY[$i]} ]]; then
			echo -e "${Orange}INFO${NC}: RC removal has started ...";
			for (( j = 0 ; j < ${#STARTED_RCs[@]} ; j++ )) do
				exec_WR ${HOSTs_ALL[$i]} "EXIT"
			done
			echo -e "${Orange}INFO${NC}: RC removed from all nodes";
			echo -e ""
			echo -e "${LRed}Experiment Failed${NC}"
			exit
		fi
	fi
done
echo -e "${Orange}INFO${NC}: RC installed on all nodes";


# --------------- Experiment orcherstration testing -------------- #
source $BEOF_DIR/test_orch.sh

# ------------------ EC->RCs clock synchronization --------------- #
# If SYNC_CLOCKS is enabled
if $SYNC_CLOCKS ; then
	echo -e "${Orange}INFO${NC}: EC and RC clocks start synchronizing"

	# Start ptpd master process on the EC node
	EC_CTRL_IF=$(ifconfig -a | grep -B1 $HOST_EC | head -n1 | awk '{print $1}')
	sudo ptpd -W -b $EC_CTRL_IF -f /tmp/ptpd_master.log -h -N 0

	# Start ptpd slave process on all RC nodes
	RC_CTRL_array=( $(exec_WR ${GROUP_ALL[MCT_ADDR]} "CTRL_IF") )
	for (( i = 0 ; i < ${#RC_CTRL_array[@]} ; i++ )) do
		RC_CTRL_IP=$(echo ${RC_CTRL_array[$i]} | cut -d# -f1)
		RC_CTRL_IF=$(echo ${RC_CTRL_array[$i]} | cut -d# -f2)
		exec_WOR $RC_CTRL_IP "truncate -s 0 /tmp/ptpd_slave.log && ptpd -g -b $RC_CTRL_IF -f /tmp/ptpd_slave.log -h && $EXEC_DIR/ptpd_sync.sh /tmp/ptpd_slave.log $OFM_MAX"
		sleep 0.05
	done

	# Wait until all RC nodes recieve ptpd synchronization messages (or entered the ptpd slave state)
	RC_PTPD_STATEs=( $(exec_WR ${GROUP_ALL[MCT_ADDR]} "tail -n 1 /tmp/ptpd_slave.log" | cut -d, -f2 | sort -u) )
	until [[ ${#RC_PTPD_STATEs[@]} -eq 1 ]] && [[ "${RC_PTPD_STATEs[0]}" == "slv" ]]; do
		sleep 1
		RC_PTPD_STATEs=( $(exec_WR ${GROUP_ALL[MCT_ADDR]} "tail -n 1 /tmp/ptpd_slave.log" | cut -d, -f2 | sort -u) )
	done

	echo -e "${Orange}INFO${NC}: Clocks are synchronized"
else
	echo -e "${Orange}INFO${NC}: EC and RC clock synchronization is disabled"
fi


# ------------------------- Wireless driver installation -------------------------- #
if [[ ${#GROUP_ALL_WIFI[@]} -gt 0 ]]; then

	# Install a Wireless driver
	wireless_modules=$(exec_WR ${GROUP_ALL_WIFI[MCT_ADDR]} "$EXEC_DIR/wireless_modules.sh" | cut -d# -f 2- | sort -u)
	exec_WR ${GROUP_ALL_WIFI[MCT_ADDR]} "modprobe -a ${wireless_modules[*]}"

	# Retrieve all Logical Wi-Fi interfaces and remove them
	LOG_IFs=( $(exec_WR ${GROUP_ALL_WIFI[MCT_ADDR]} "find /sys/class/ieee80211/phy*/device/net -maxdepth 1 -mindepth 1" | cut -d/ -f 8) )
	for (( i = 0 ; i < ${#LOG_IFs[@]} ; i++ )) do
		# Sometimes a Wi-Fi interface can be used as a control interface. In such a case, do not delete the Wi-Fi interface
#		if [[ "${LOG_IFs[$i]}" != "$RC_CTRL_IF" ]]; then
			exec_WOR ${GROUP_ALL_WIFI[MCT_ADDR]} "if iw dev ${LOG_IFs[$i]} info &> /dev/null; then iw dev ${LOG_IFs[$i]} del; fi"
#		fi
		sleep 0.05
	done

	# By default udevd controls interface naming according to rules specified in "/etc/udev/rules.d/70-persistent-net.rules"
	# Stop udev from executing interface naming events
	exec_WR ${GROUP_ALL_WIFI[MCT_ADDR]} "udevadm control --stop-exec-queue"
fi


# ------------------------- Wi-Fi AP interface handler -------------------------- #

# Create a new master interface
for (( i = 0 ; i < $AP_IF_CNT ; i++ )) do
	AP_CTRL_IPs=(${AP_CTRL_IP[$i]//,/ })
	for (( j = 0 ; j < ${#AP_CTRL_IPs[@]} ; j++ )) do
		AP_PHY=$(MATCH_LOG_IF_to_PHY_IF ${AP_CTRL_IPs[$j]} ${AP_IF[$i]})
		exec_WOR ${AP_CTRL_IPs[$j]} "iw phy $AP_PHY interface add ${AP_IF[$i]} type managed"
	done
	sleep 0.05
done
# Optional: IP address configuration
for (( i = 0 ; i < $AP_IF_CNT ; i++ )) do
	if [[ ${AP_IF_IP[$i]} ]]; then
		AP_CTRL_IPs=(${AP_CTRL_IP[$i]//,/ })
		AP_IF_IPs=(${AP_IF_IP[$i]//,/ })
		for (( j = 0 ; j < ${#AP_CTRL_IPs[@]} ; j++ )) do
			exec_WOR ${AP_CTRL_IPs[$j]} "ip addr add ${AP_IF_IPs[$j]}/24 dev ${AP_IF[$i]}"
		done
		sleep 0.05
	fi
done
# Optional: Interface Tx_power adjustment
for (( i = 0 ; i < $AP_IF_CNT ; i++ )) do
	if [[  ${AP_TX_POWER[$i]} ]]; then
		exec_WOR ${AP_MCT_ADDR[$i]} "iw dev ${AP_IF[$i]} set txpower fixed $((${AP_TX_POWER[$i]}*100))"
		sleep 0.05
	fi
done
# AP configuration file
for (( i = 0 ; i < $AP_IF_CNT ; i++ )) do
	# User supplied hostapd configuration file
	if [[ ${AP_CONFIG[$i]} ]]; then
		# parse and escape \n and " characters
		content=$(cat ${AP_CONFIG[$i]} | sed -e ':a;N;$!ba;s/\n/\\n/g' -e 's/"/\\"/g')
		# replace $config variable with full path name
		content="${content//\$config/$BEOF_DIR/config/hostapd}"
		exec_WOR ${AP_MCT_ADDR[$i]} "printf \"$content\n\" > /tmp/hostapd.${AP_IF[$i]}.conf"
	# If not, create a simple hostapd configuration file
	else
		exec_WOR ${AP_MCT_ADDR[$i]} "printf \"ctrl_interface=/var/run/hostapd\n\ndriver=nl80211\ninterface=${AP_IF[$i]}\nssid=${AP_ESSID[$i]}\nchannel=${AP_CHANNEL[$i]}\nhw_mode=${AP_HW_MODE[$i]}\" > /tmp/hostapd.${AP_IF[$i]}.conf"
	fi
	sleep 0.05
done
# start AP
for (( i = 0 ; i < $AP_IF_CNT ; i++ )) do
	exec_WOR ${AP_MCT_ADDR[$i]} "hostapd -B /tmp/hostapd.${AP_IF[$i]}.conf"
	sleep 0.05

	# Display AP status
	AP_CTRL_IPs=(${AP_CTRL_IP[$i]//,/ })
	for (( j = 0 ; j < ${#AP_CTRL_IPs[@]} ; j++ )) do
		# User supplied hostapd configuration file
		if [[ ${AP_CONFIG[$i]} ]]; then
			echo -e "${Orange}INFO${NC}: Access point @ ${AP_CTRL_IPs[$j]} created using [INT=${AP_IF[$i]} and CONFIG_FILE=${AP_CONFIG[$i]}]"
		else
			echo -e "${Orange}INFO${NC}: Access point @ ${AP_CTRL_IPs[$j]} created using [INT=${AP_IF[$i]}, CH=${AP_CHANNEL[$i]} and ESSID=${AP_ESSID[$i]}]"
		fi
	done
done


# ------------------------- Wi-Fi CLIENT interface handler -------------------------- #

# Create a new managed interface
for (( i = 0 ; i < $CLIENT_IF_CNT ; i++ )) do
	CLIENT_CTRL_IPs=(${CLIENT_CTRL_IP[$i]//,/ })
	for (( j = 0 ; j < ${#CLIENT_CTRL_IPs[@]} ; j++ )) do
		CLIENT_PHY=$(MATCH_LOG_IF_to_PHY_IF ${CLIENT_CTRL_IPs[$j]} ${CLIENT_IF[$i]})
		exec_WOR ${CLIENT_CTRL_IPs[$j]} "iw phy $CLIENT_PHY interface add ${CLIENT_IF[$i]} type managed"
	done
	sleep 0.05
done
# Optional: IP address configuration
for (( i = 0 ; i < $CLIENT_IF_CNT ; i++ )) do
	if [[ ${CLIENT_IF_IP[$i]} ]]; then
		CLIENT_CTRL_IPs=(${CLIENT_CTRL_IP[$i]//,/ })
		CLIENT_IF_IPs=(${CLIENT_IF_IP[$i]//,/ })
		for (( j = 0 ; j < ${#CLIENT_CTRL_IPs[@]} ; j++ )) do
			exec_WOR ${CLIENT_CTRL_IPs[$j]} "ip addr add ${CLIENT_IF_IPs[$j]}/24 dev ${CLIENT_IF[$i]}"
		done
		sleep 0.05
	fi
done
# Optional: Interface tx_power adjustment
for (( i = 0 ; i < $CLIENT_IF_CNT ; i++ )) do
	if [[ ${CLIENT_TX_POWER[$i]} ]]; then
		exec_WOR ${CLIENT_MCT_ADDR[$i]} "iw dev ${CLIENT_IF[$i]} set txpower fixed $((${CLIENT_TX_POWER[$i]}*100))"
		sleep 0.05
	fi
done
# CLIENT configuration file
for (( i = 0 ; i < $CLIENT_IF_CNT ; i++ )) do
	# User supplied hostapd configuration file
	if [[ ${CLIENT_CONFIG[$i]} ]]; then
		# parse and escape \n and " characters
		content=$(cat ${CLIENT_CONFIG[$i]} | sed -e ':a;N;$!ba;s/\n/\\n/g' -e 's/"/\\"/g')
		exec_WOR ${CLIENT_MCT_ADDR[$i]} "printf \"$content\n\" > /tmp/wpa_supplicant.${CLIENT_IF[$i]}.conf"
	# If not, create a simple wpa_supplicant configuration file
	else
		exec_WOR ${CLIENT_MCT_ADDR[$i]} "printf \"ctrl_interface=/var/run/wpa_supplicant\n\nnetwork={\n\tssid=\\\"${CLIENT_ESSID[$i]}\\\"\n\tkey_mgmt=NONE\n}\" > /tmp/wpa_supplicant.${CLIENT_IF[$i]}.conf"
	fi
	sleep 0.05
done
# connect to AP
for (( i = 0 ; i < $CLIENT_IF_CNT ; i++ )) do
	exec_WOR ${CLIENT_MCT_ADDR[$i]} "wpa_supplicant -B -c /tmp/wpa_supplicant.${CLIENT_IF[$i]}.conf -i ${CLIENT_IF[$i]}"
	sleep 0.05
done
# Wait until all CLIENTs are associated to APs
for (( i = 0 ; i < $CLIENT_IF_CNT ; i++ )) do
	CLIENT_CTRL_IPs=(${CLIENT_CTRL_IP[$i]//,/ })
	for (( j = 0 ; j < ${#CLIENT_CTRL_IPs[@]} ; j++ )) do
		status=$(exec_WR ${CLIENT_CTRL_IPs[$j]} "wpa_cli -i ${CLIENT_IF[$i]} status | grep wpa_state" | cut -d= -f 2)
		until [[ $status == "COMPLETED" ]]; do
			sleep 1
			status=$(exec_WR ${CLIENT_CTRL_IPs[$j]} "wpa_cli -i ${CLIENT_IF[$i]} status | grep wpa_state" | cut -d= -f 2)
		done

		# Display CLIENT status
		if [[ ${CLIENT_CONFIG[$i]} ]]; then
			echo -e "${Orange}INFO${NC}: Node @ ${CLIENT_CTRL_IPs[$j]} joined access point using [INT=${CLIENT_IF[$i]} and CONFIG_FILE=${CLIENT_CONFIG[$i]}]"
		else
			echo -e "${Orange}INFO${NC}: Node @ ${CLIENT_CTRL_IPs[$j]} joined access point using [INT=${CLIENT_IF[$i]} and ESSID=${CLIENT_ESSID[$i]}]"
		fi
	done
done


# ------------------------- Wi-Fi ADHOC interface handler -------------------------- #

# Create a new adhoc interface
for (( i = 0 ; i < $ADHOC_IF_CNT ; i++ )) do
	ADHOC_CTRL_IPs=(${ADHOC_CTRL_IP[$i]//,/ })
	for (( j = 0 ; j < ${#ADHOC_CTRL_IPs[@]} ; j++ )) do
		ADHOC_PHY=$(MATCH_LOG_IF_to_PHY_IF ${ADHOC_CTRL_IPs[$j]} ${ADHOC_IF[$i]})
		exec_WOR ${ADHOC_CTRL_IPs[$j]} "iw phy $ADHOC_PHY interface add ${ADHOC_IF[$i]} type ibss"
	done
	sleep 0.05
done
# Optional: IP address configuration
for (( i = 0 ; i < $ADHOC_IF_CNT ; i++ )) do
	if [[ ${ADHOC_IF_IP[$i]} ]]; then
		ADHOC_CTRL_IPs=(${ADHOC_CTRL_IP[$i]//,/ })
		ADHOC_IF_IPs=(${ADHOC_IF_IP[$i]//,/ })
		for (( j = 0 ; j < ${#ADHOC_CTRL_IPs[@]} ; j++ )) do
			exec_WOR ${ADHOC_CTRL_IPs[$j]} "ip addr add ${ADHOC_IF_IPs[$j]}/24 dev ${ADHOC_IF[$i]}"
		done
		sleep 0.05
	fi
done
# Optional: Interface tx_power adjustment
for (( i = 0 ; i < $ADHOC_IF_CNT ; i++ )) do
	if [[ ${ADHOC_TX_POWER[$i]} ]]; then
		exec_WOR ${ADHOC_MCT_ADDR[$i]} "iw dev ${ADHOC_IF[$i]} set txpower fixed $((${ADHOC_TX_POWER[$i]}*100))"
		sleep 0.05
	fi
done
# bring the inteface up
for (( i = 0 ; i < $ADHOC_IF_CNT ; i++ )) do
	exec_WOR ${ADHOC_MCT_ADDR[$i]} "ifconfig ${ADHOC_IF[$i]} up"
	sleep 0.05
done
# join or create the ibss/adhoc network on the selected frequency and essid
for (( i = 0 ; i < $ADHOC_IF_CNT ; i++ )) do
	ADHOC_FREQ=$(channel_to_freq ${ADHOC_CHANNEL[$i]})
	exec_WOR ${ADHOC_MCT_ADDR[$i]} "iw dev ${ADHOC_IF[$i]} ibss join ${ADHOC_ESSID[$i]} $ADHOC_FREQ"
	sleep 0.05
done

# Wait until all ADHOCs are associated
for (( i = 0 ; i < $ADHOC_IF_CNT ; i++ )) do
	# Wait until all ADHOC connections are established
	ADHOC_CTRL_IPs=(${ADHOC_CTRL_IP[$i]//,/ })
	for (( j = 0 ; j < ${#ADHOC_CTRL_IPs[@]} ; j++ )) do
		status=$(exec_WR ${ADHOC_CTRL_IPs[$j]} "iw dev ${ADHOC_IF[$i]} link | grep IBSS" | cut -d# -f 2 | cut -d" " -f 1)
		until [[ $status == "Joined" ]]; do
			sleep 1
			status=$(exec_WR ${ADHOC_CTRL_IPs[$j]} "iw dev ${ADHOC_IF[$i]} link | grep IBSS" | cut -d# -f 2 | cut -d" " -f 1)
		done

		# Display ADHOC status
		echo -e "${Orange}INFO${NC}: Node @ ${ADHOC_CTRL_IPs[$j]} created/joined adhoc network using [INT=${ADHOC_IF[$i]}, CH=${ADHOC_CHANNEL[$i]}, ESSID=${ADHOC_ESSID[$i]}]"
	done
done


# ------------------------- Wi-Fi MONITOR interface handler -------------------------- #

# Create a new monitor interface
for (( i = 0 ; i < $MONITOR_IF_CNT ; i++ )) do
	MONITOR_CTRL_IPs=(${MONITOR_CTRL_IP[$i]//,/ })
	for (( j = 0 ; j < ${#MONITOR_CTRL_IPs[@]} ; j++ )) do
		MONITOR_PHY=$(MATCH_LOG_IF_to_PHY_IF ${MONITOR_CTRL_IPs[$j]} ${MONITOR_IF[$i]})
		exec_WOR ${MONITOR_CTRL_IPs[$j]} "iw phy $MONITOR_PHY interface add ${MONITOR_IF[$i]} type monitor"
	done
	sleep 0.05
done
# bring the inteface up
for (( i = 0 ; i < $MONITOR_IF_CNT ; i++ )) do
	exec_WOR ${MONITOR_MCT_ADDR[$i]} "ifconfig ${MONITOR_IF[$i]} up"
	sleep 0.05

	# Display MONITOR status
	MONITOR_CTRL_IPs=(${MONITOR_CTRL_IP[$i]//,/ })
	for (( j = 0 ; j < ${#MONITOR_CTRL_IPs[@]} ; j++ )) do
		echo -e "${Orange}INFO${NC}: Node @ ${MONITOR_CTRL_IPs[$j]} created monitor interface ${MONITOR_IF[$i]}"
	done
done
# Optional: monitor channel adjustment
for (( i = 0 ; i < $MONITOR_IF_CNT ; i++ )) do
	if [[ ${MONITOR_CHANNEL[$i]} ]]; then
		exec_WOR ${MONITOR_MCT_ADDR[$i]} "iw dev ${MONITOR_IF[$i]} set channel ${MONITOR_CHANNEL[$i]}"
		sleep 0.05
	fi
done


# ------------------------- BT GN interface handler -------------------------- #

# Bring BT hci* interface UP, enable page/inquiry scan and configure AFH mode
for (( i = 0 ; i < $GN_IF_CNT ; i++ )) do
	exec_WR ${GN_MCT_ADDR[$i]} "hciconfig ${GN_PHY[$i]} up && hciconfig ${GN_PHY[$i]} piscan && hciconfig ${GN_PHY[$i]} afhmode ${GN_AFH_MODE[$i]}"
done

# Listen for BT Client connection
if [[ ${#GROUP_ALL_GN[@]} -gt 0 ]]; then
	exec_WOR ${GROUP_ALL_GN[MCT_ADDR]} "pand --listen --role GN --master"
	sleep 0.05
fi


# ------------------------- BT PANU/GN interface handler -------------------------- #

# Bring BT physical interface UP, enable page/inquiry scan and configure AFH mode
for (( i = 0 ; i < $PANU_IF_CNT ; i++ )) do
	exec_WOR ${PANU_MCT_ADDR[$i]} "hciconfig ${PANU_PHY[$i]} up && hciconfig ${PANU_PHY[$i]} piscan && hciconfig ${PANU_PHY[$i]} afhmode ${PANU_AFH_MODE[$i]}"
	sleep 0.05
done
# Connect to a Master BT device
for (( i = 0 ; i < $PANU_IF_CNT ; i++ )) do
	PANU_CTRL_IPs=(${PANU_CTRL_IP[$i]//,/ })
	PANU_REMOTE_CTRL_IPs=(${PANU_REMOTE_CTRL_IP[$i]//,/ })
	for (( j = 0 ; j < ${#PANU_CTRL_IPs[@]} ; j++ )) do
		MA_BT_MAC=$(exec_WR ${PANU_REMOTE_CTRL_IPs[$j]} "hciconfig ${PANU_REMOTE_PHY[$i]} | grep Address" | cut -d" " -f 4 )
		exec_WOR ${PANU_CTRL_IPs[$j]} "pand --connect $MA_BT_MAC"
	done
	sleep 0.05
done
# Wait until all PAN users are connected to Master BTs
for (( i = 0 ; i < $PANU_IF_CNT ; i++ )) do
	PANU_CTRL_IPs=(${PANU_CTRL_IP[$i]//,/ })
	for (( j = 0 ; j < ${#PANU_CTRL_IPs[@]} ; j++ )) do
		status=$(exec_WR ${PANU_CTRL_IPs[$j]} "[ -d /sys/class/net/${PANU_IF[$i]} ] && echo CONNECTED || echo NOT CONNECTED" | cut -d# -f 2- )
		until [[ $status == "CONNECTED" ]]; do
			sleep 1
			status=$(exec_WR ${PANU_CTRL_IPs[$j]} "[ -d /sys/class/net/${PANU_IF[$i]} ] && echo CONNECTED || echo NOT CONNECTED" | cut -d# -f 2-)
		done
		echo -e "${Orange}INFO${NC}: Node @ ${PANU_CTRL_IPs[$j]} connected to a GN master Bluetooth as PANU [INT=${PANU_PHY[$i]} and AFHMODE=${PANU_AFH_MODE[$i]}]"
	done
done
# bring GN/PANU logical intefaces up
for (( i = 0 ; i < $GN_IF_CNT ; i++ )) do
	exec_WOR ${GN_MCT_ADDR[$i]} "ifconfig ${GN_IF[$i]} up"
	sleep 0.05
done
for (( i = 0 ; i < $PANU_IF_CNT ; i++ )) do
	exec_WOR ${PANU_MCT_ADDR[$i]} "ifconfig ${PANU_IF[$i]} up"
	sleep 0.05
done
# Optional: GN/PANU IP address configuration
for (( i = 0 ; i < $GN_IF_CNT ; i++ )) do
	if [[ ${GN_IF_IP[$i]} ]]; then
		GN_CTRL_IPs=(${GN_CTRL_IP[$i]//,/ })
		GN_IF_IPs=(${GN_IF_IP[$i]//,/ })
		for (( j = 0 ; j < ${#GN_CTRL_IPs[@]} ; j++ )) do
			exec_WOR ${GN_CTRL_IPs[$j]} "ip addr add ${GN_IF_IPs[$j]}/24 dev ${GN_IF[$i]}"
		done
		sleep 0.05
	fi
done
for (( i = 0 ; i < $PANU_IF_CNT ; i++ )) do
	if [[ ${PANU_IF_IP[$i]} ]]; then
		PANU_CTRL_IPs=(${PANU_CTRL_IP[$i]//,/ })
		PANU_IF_IPs=(${PANU_IF_IP[$i]//,/ })
		for (( j = 0 ; j < ${#PANU_CTRL_IPs[@]} ; j++ )) do
			exec_WOR ${PANU_CTRL_IPs[$j]} "ip addr add ${PANU_IF_IPs[$j]}/24 dev ${PANU_IF[$i]}"
		done
		sleep 0.05
	fi
done


