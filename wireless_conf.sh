#!/bin/bash

# -------------------- GROUP config verification --------------------- #
#TODO


# -------------------------- Wireless interface configuration -------------------------- #

# AP array parameters declaration
declare -a AP_CTRL_IP=()
declare -a AP_MCT_ADDR=()
declare -a AP_IF=()
declare -a AP_CONFIG=()
declare -a AP_HW_MODE=()
declare -a AP_CHANNEL=()
declare -a AP_ESSID=()
declare -a AP_TX_POWER=()
declare -a AP_IF_IP=()
AP_IF_CNT=0

# CLIENT array parameters declaration
declare -a CLIENT_CTRL_IP=()
declare -a CLIENT_MCT_ADDR=()
declare -a CLIENT_IF=()
declare -a CLIENT_CONFIG=()
declare -a CLIENT_ESSID=()
declare -a CLIENT_TX_POWER=()
declare -a CLIENT_IF_IP=()
CLIENT_IF_CNT=0

# ADHOC array parameters declaration
declare -a ADHOC_CTRL_IP=()
declare -a ADHOC_MCT_ADDR=()
declare -a ADHOC_IF=()
declare -a ADHOC_CHANNEL=()
declare -a ADHOC_ESSID=()
declare -a ADHOC_TX_POWER=()
declare -a ADHOC_IF_IP=()
ADHOC_IF_CNT=0

# MONITOR array parameters declaration
declare -a MONITOR_CTRL_IP=()
declare -a MONITOR_MCT_ADDR=()
declare -a MONITOR_IF=()
declare -a MONITOR_CHANNEL=()
MONITOR_IF_CNT=0

# GN array parameters declaration
declare -a GN_CTRL_IP=()
declare -a GN_MCT_ADDR=()
declare -a GN_IF=()
declare -a GN_PHY=()
declare -a GN_AFH_MODE=()
declare -a GN_IF_IP=()
GN_IF_CNT=0

# PANU array parameters declaration
declare -a PANU_CTRL_IP=()
declare -a PANU_MCT_ADDR=()
declare -a PANU_IF=()
declare -a PANU_PHY=()
declare -a PANU_AFH_MODE=()
declare -a PANU_REMOTE_IF=()
declare -a PANU_REMOTE_PHY=()
declare -a PANU_REMOTE_CTRL_IP=()
declare -a PANU_IF_IP=()
PANU_IF_CNT=0

# Retrieve all user defined GROUP names
GROUP_NAMEs=( $(declare -p | grep "declare -A GROUP_" | grep -vE GEDIT_CURRENT_LINE | grep -vE Dbg_source_* | cut -d_ -f 2- | cut -d= -f 1) )
for NAME in ${GROUP_NAMEs[*]}; do
	# Per node configuration parameter
	CTRL_IP=$(eval  echo \${GROUP_$NAME[CTRL_IP]})
	MCT_ADDR=$(eval echo \${GROUP_$NAME[MCT_ADDR]})

	# Per interface configuration parameter
	IF_STR=$(eval echo \${GROUP_$NAME[IF]})
	# If interface is defined for the group
	if [[ -n "$IF_STR" ]]; then
		MODE_STR=$(eval echo \${GROUP_$NAME[MODE]})
		CONFIG_STR=$(eval echo \${GROUP_$NAME[CONFIG]})
		HW_MODE_STR=$(eval echo \${GROUP_$NAME[HW_MODE]})
		CHANNEL_STR=$(eval echo \${GROUP_$NAME[CHANNEL]})
		ESSID_STR=$(eval echo \${GROUP_$NAME[ESSID]})
		TX_POWER_STR=$(eval echo \${GROUP_$NAME[TX_POWER]})
		IF_IP_STR=$(eval echo \${GROUP_$NAME[IF_IP]})
		AFH_MODE_STR=$(eval echo \${GROUP_$NAME[AFH_MODE]})
		REMOTE_IF_STR=$(eval echo \${GROUP_$NAME[REMOTE_IF]})
		REMOTE_CTRL_IP_STR=$(eval echo \${GROUP_$NAME[REMOTE_CTRL_IP]})

		IF_ARRAY=(${IF_STR//:/ })
		MODE_ARRAY=(${MODE_STR//:/ })
		CONFIG_ARRAY=(${CONFIG_STR//:/ })
		HW_MODE_ARRAY=(${HW_MODE_STR//:/ })
		CHANNEL_ARRAY=(${CHANNEL_STR//:/ })
		ESSID_ARRAY=(${ESSID_STR//:/ })
		TX_POWER_ARRAY=(${TX_POWER_STR//:/ })
		IF_IP_ARRAY=(${IF_IP_STR//:/ })
		AFH_MODE_ARRAY=(${AFH_MODE_STR//:/ })
		REMOTE_IF_ARRAY=(${REMOTE_IF_STR//:/ })
		REMOTE_CTRL_IP_ARRAY=(${REMOTE_CTRL_IP_STR//:/ })

		# Iterate through each interface of the group
		for (( i = 0 ; i < ${#IF_ARRAY[@]} ; i++ )) do
			IF=${IF_ARRAY[$i]}
			MODE=${MODE_ARRAY[$i]}
			CONFIG=${CONFIG_ARRAY[$i]}
			HW_MODE=${HW_MODE_ARRAY[$i]}
			CHANNEL=${CHANNEL_ARRAY[$i]}
			ESSID=${ESSID_ARRAY[$i]}
			TX_POWER=${TX_POWER_ARRAY[$i]}
			IF_IP=${IF_IP_ARRAY[$i]}
			AFH_MODE=${AFH_MODE_ARRAY[$i]}
			REMOTE_IF=${REMOTE_IF_ARRAY[$i]}
			REMOTE_CTRL_IP=${REMOTE_CTRL_IP_ARRAY[$i]}

			if [[ $MODE == "master" ]]; then
				# Fill up AP parameters
				AP_CTRL_IP[AP_IF_CNT]=$CTRL_IP
				AP_MCT_ADDR[AP_IF_CNT]=$MCT_ADDR
				AP_IF[AP_IF_CNT]=$IF
				AP_PHY[AP_IF_CNT]=phy${IF:${#IF}-1:1}
				AP_CONFIG[AP_IF_CNT]=$CONFIG
				AP_HW_MODE[AP_IF_CNT]=$HW_MODE
				AP_CHANNEL[AP_IF_CNT]=$CHANNEL
				AP_ESSID[AP_IF_CNT]=$ESSID
				AP_TX_POWER[AP_IF_CNT]=$TX_POWER
				AP_IF_IP[AP_IF_CNT]=$IF_IP

				# Increment AP counter
				AP_IF_CNT=$((AP_IF_CNT+1))

			elif [[ $MODE == "managed" ]]; then
				# Fill up CLIENT parameters
				CLIENT_CTRL_IP[CLIENT_IF_CNT]=$CTRL_IP
				CLIENT_MCT_ADDR[CLIENT_IF_CNT]=$MCT_ADDR
				CLIENT_IF[CLIENT_IF_CNT]=$IF
				CLIENT_PHY[CLIENT_IF_CNT]=phy${IF:${#IF}-1:1}
				CLIENT_CONFIG[CLIENT_IF_CNT]=$CONFIG
				CLIENT_ESSID[CLIENT_IF_CNT]=$ESSID
				CLIENT_TX_POWER[CLIENT_IF_CNT]=$TX_POWER
				CLIENT_IF_IP[CLIENT_IF_CNT]=$IF_IP

				# Increment CLIENT counter
				CLIENT_IF_CNT=$((CLIENT_IF_CNT+1))

			elif [[ $MODE == "adhoc" ]]; then
				# Fill up ADHOC parameters
				ADHOC_CTRL_IP[ADHOC_IF_CNT]=$CTRL_IP
				ADHOC_MCT_ADDR[ADHOC_IF_CNT]=$MCT_ADDR
				ADHOC_IF[ADHOC_IF_CNT]=$IF
				ADHOC_PHY[ADHOC_IF_CNT]=phy${IF:${#IF}-1:1}
				ADHOC_CHANNEL[ADHOC_IF_CNT]=$CHANNEL
				ADHOC_ESSID[ADHOC_IF_CNT]=$ESSID
				ADHOC_TX_POWER[ADHOC_IF_CNT]=$TX_POWER
				ADHOC_IF_IP[ADHOC_IF_CNT]=$IF_IP

				# Increment ADHOC counter
				ADHOC_IF_CNT=$((ADHOC_IF_CNT+1))

			elif [[ $MODE == "monitor" ]]; then
				# Fill up MONITOR parameters
				MONITOR_CTRL_IP[MONITOR_IF_CNT]=$CTRL_IP
				MONITOR_MCT_ADDR[MONITOR_IF_CNT]=$MCT_ADDR
				MONITOR_IF[MONITOR_IF_CNT]=$IF
				MONITOR_CHANNEL[AP_IF_CNT]=$CHANNEL

				# Increment MONITOR counter
				MONITOR_IF_CNT=$((MONITOR_IF_CNT+1))

			elif [[ $MODE == "GN" ]]; then
				# Fill up Bluetooth GN parameters
				GN_CTRL_IP[GN_IF_CNT]=$CTRL_IP
				GN_MCT_ADDR[GN_IF_CNT]=$MCT_ADDR
				GN_IF[GN_IF_CNT]=$IF
				GN_PHY[GN_IF_CNT]=hci${IF:${#IF}-1:1}
				GN_AFH_MODE[GN_IF_CNT]=$AFH_MODE
				GN_IF_IP[GN_IF_CNT]=$IF_IP

				# Increment GN counter
				GN_IF_CNT=$((GN_IF_CNT+1))

			elif [[ $MODE == "PANU" ]]; then
				# Fill up Bluetooth PANU parameters
				PANU_CTRL_IP[PANU_IF_CNT]=$CTRL_IP
				PANU_MCT_ADDR[PANU_IF_CNT]=$MCT_ADDR
				PANU_IF[PANU_IF_CNT]=$IF
				PANU_PHY[PANU_IF_CNT]=hci${IF:${#IF}-1:1}
				PANU_AFH_MODE[PANU_IF_CNT]=$AFH_MODE
				PANU_REMOTE_IF[PANU_IF_CNT]=$REMOTE_IF
				PANU_REMOTE_PHY[PANU_IF_CNT]=hci${REMOTE_IF:${#REMOTE_IF}-1:1}
				PANU_REMOTE_CTRL_IP[PANU_IF_CNT]=$REMOTE_CTRL_IP
				PANU_IF_IP[PANU_IF_CNT]=$IF_IP

				# Increment PANU counter
				PANU_IF_CNT=$((PANU_IF_CNT+1))
			fi
		done
	fi
done

# --------------------- GROUP_ALL_WIFI definition --------------------- #
WIFI_NODEs=($(printf "%s\n%s\n%s\n%s\n" ${AP_CTRL_IP[*]//,/ } ${CLIENT_CTRL_IP[*]//,/ } ${ADHOC_CTRL_IP[*]//,/ } ${MONITOR_CTRL_IP[*]//,/ } | sort -u))
if [[ ${#WIFI_NODEs[@]} -gt 0 ]]; then
	declare -A GROUP_ALL_WIFI=(
		[CTRL_IP]=$(IFS=, eval echo '"${WIFI_NODEs[*]}"')
		[MCT_ADDR]=$(eval echo $RAND_MCT_ADDR)
	)
	GROUP_NAMEs+=("ALL_WIFI")
fi

# --------------------- GROUP_ALL_BT definition --------------------- #
BT_NODEs=($(printf "%s\n%s\n" ${GN_CTRL_IP[*]//,/ } ${PANU_CTRL_IP[*]//,/ } | sort -u))
if [[ ${#BT_NODEs[@]} -gt 0 ]]; then
	declare -A GROUP_ALL_BT=(
		[CTRL_IP]=$(IFS=, eval echo '"${BT_NODEs[*]}"')
		[MCT_ADDR]=$(eval echo $RAND_MCT_ADDR)
	)
	GROUP_NAMEs+=("ALL_BT")
fi

# --------------------- GROUP_ALL_AP definition --------------------- #
if [[ $AP_IF_CNT -gt 0 ]]; then
	declare -A GROUP_ALL_AP=(
		[CTRL_IP]=$(IFS=, eval echo '"${AP_CTRL_IP[*]}"')
		[MCT_ADDR]=$(eval echo $RAND_MCT_ADDR)
	)
	GROUP_NAMEs+=("ALL_AP")
fi

# --------------------- GROUP_ALL_CLIENT definition --------------------- #
if [[ $CLIENT_IF_CNT -gt 0 ]]; then
	declare -A GROUP_ALL_CLIENT=(
		[CTRL_IP]=$(IFS=, eval echo '"${CLIENT_CTRL_IP[*]}"')
		[MCT_ADDR]=$(eval echo $RAND_MCT_ADDR)
	)
	GROUP_NAMEs+=("ALL_CLIENT")
fi

# --------------------- GROUP_ALL_ADHOC definition --------------------- #
if [[ $ADHOC_IF_CNT -gt 0 ]]; then
	declare -A GROUP_ALL_ADHOC=(
		[CTRL_IP]=$(IFS=, eval echo '"${ADHOC_CTRL_IP[*]}"')
		[MCT_ADDR]=$(eval echo $RAND_MCT_ADDR)
	)
	GROUP_NAMEs+=("ALL_ADHOC")
fi

# --------------------- GROUP_ALL_MONITOR definition --------------------- #
if [[ $MONITOR_IF_CNT -gt 0 ]]; then
	declare -A GROUP_ALL_MONITOR=(
		[CTRL_IP]=$(IFS=, eval echo '"${MONITOR_CTRL_IP[*]}"')
		[MCT_ADDR]=$(eval echo $RAND_MCT_ADDR)
	)
	GROUP_NAMEs+=("ALL_MONITOR")
fi

# --------------------- GROUP_ALL_GN definition --------------------- #
if [[ $GN_IF_CNT -gt 0 ]]; then
	declare -A GROUP_ALL_GN=(
		[CTRL_IP]=$(IFS=, eval echo '"${GN_CTRL_IP[*]}"')
		[MCT_ADDR]=$(eval echo $RAND_MCT_ADDR)
	)
	GROUP_NAMEs+=("ALL_GN")
fi

# --------------------- GROUP_ALL_PANU definition --------------------- #
if [[ $PANU_IF_CNT -gt 0 ]]; then
	declare -A GROUP_ALL_PANU=(
		[CTRL_IP]=$(IFS=, eval echo '"${PANU_CTRL_IP[*]}"')
		[MCT_ADDR]=$(eval echo $RAND_MCT_ADDR)
	)
	GROUP_NAMEs+=("ALL_PANU")
fi

# --------------------- GROUP_ALL definition --------------------- #
# From all defined GROUPs, retrieve control IPs
CTRL_IPs=()
for (( i = 0 ; i < ${#GROUP_NAMEs[@]} ; i++ )) do
	CTRL_IPs[i]=`eval echo \\\${GROUP_${GROUP_NAMEs[$i]}[CTRL_IP]}`
done

# Create the GROUP_ALL associative array
declare -A GROUP_ALL=(
	[CTRL_IP]=$(IFS=, eval echo '"${CTRL_IPs[*]}"')
	[MCT_ADDR]=$(eval echo $RAND_MCT_ADDR)
	[NAME]=$(IFS=, eval echo '"${GROUP_NAMEs[*]}"')
)

