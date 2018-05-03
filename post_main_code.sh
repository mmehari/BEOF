#!/bin/bash
sleep 0.05

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

# If SYNC_CLOCKS is enabled, stop synchronizing RCs and EC
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

