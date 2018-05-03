#!/bin/bash
# -------------------- System: Global Variables ----------------------- #
BEOF_DIR="/root/BEOF"

HOST_EC="172.17.0.2"					# EC host IP address
PORT_EC=8800						# EC port number
PORT_RC=8800						# RC port number
EC_RECV_SOCK_TIMEOUT=5					# Maximum time (in seconds) the EC will wait for RC results during exec_WR call
RC_START_RETRIES=3					# Maximum number of RC connection retries incase of failure
SYNC_CLOCKS=false					# true = turn ON, false = turn OFF synchronization
OFM_MAX=0.001						# Maximum allowed Offset From Master (OFM) in seconds
VERBOSE=true						# true = turn ON, false = turn OFF verbose output
GRAPH_path="http://$HOST_EC/GRAPH/GRAPH.html"		# Graphing tool path
OEMV_path="http://$HOST_EC/OEMV/OEMV.html"		# Orchestration and Error Message Viewer (OEMV) path

source $BEOF_DIR/global_var.sh
# -------------------- User section: Global Variables ----------------- #

RC1_CTRL_IP="172.17.0.3"
RC2_CTRL_IP="172.17.0.4"
RC3_CTRL_IP="172.17.0.5"
RC4_CTRL_IP="172.17.0.6"

declare -A GROUP_RC1=(
	[CTRL_IP]=$RC1_CTRL_IP
	[MCT_ADDR]=$(eval echo $RAND_MCT_ADDR)
)

declare -A GROUP_RC2=(
	[CTRL_IP]=$RC2_CTRL_IP
	[MCT_ADDR]=$(eval echo $RAND_MCT_ADDR)
)

declare -A GROUP_RC3=(
	[CTRL_IP]=$RC3_CTRL_IP
	[MCT_ADDR]=$(eval echo $RAND_MCT_ADDR)
)

declare -A GROUP_RC4=(
	[CTRL_IP]=$RC4_CTRL_IP
	[MCT_ADDR]=$(eval echo $RAND_MCT_ADDR)
)

# -------------------- System: Function Definition -------------------- #
source $BEOF_DIR/func_def.sh
# -------------------- User section: Function Definition -------------- #
# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #
# Code inside sig_handler() function is executed up on [SIGHUP, SIGINT, SIGQUIT, SIGABRT, SIGKILL] system signals #
# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #
#sig_handler()
#{
#}
# -------------------- System: Main Code ------------------------------ #
source $BEOF_DIR/wireless_conf.sh
source $BEOF_DIR/pre_main_code.sh

# -------------------- User section: Main Code ------------------------------ #

exec_WR ${GROUP_RC1[MCT_ADDR]} "ping -c 2 ${GROUP_RC2[CTRL_IP]}"
exec_WR ${GROUP_RC1[MCT_ADDR]} "ping -c 2 ${GROUP_RC3[CTRL_IP]}"
exec_WR ${GROUP_RC1[MCT_ADDR]} "ping -c 2 ${GROUP_RC4[CTRL_IP]}"

# -------------------- System: Main Code ------------------------------ #
source $BEOF_DIR/post_main_code.sh


