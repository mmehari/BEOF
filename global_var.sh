#!/bin/bash
# These variables are important for the proper execution of the experiment and it is
# adviced not to delete or modify them else where in the experiment description.

# RC stream socket port number
PORT_RC_CONNECT="12345"

# random Multicast address generator
RAND_MCT_ADDR='`shuf -i 224-239 -n 1`.$(($RANDOM%256)).$(($RANDOM%256)).$(($RANDOM%256))'

# Executable programs directory
EXEC_DIR="${BEOF_DIR}/exec"

# Experiment Controller (EC) executable path
EC_EXEC="$EXEC_DIR/EC/EC"

# Resource Controller (RC) executable path
RC_EXEC="$EXEC_DIR/RC/RC"

# Temporary directory
TMP_DIR="${BEOF_DIR}/tmp"

# Orchestration and Error Message Viewer (OEMV) directory
OEMV_DIR="${TMP_DIR}/OEMV"

# Experiment ID
EXPR_ID="BEOF-`date +"%Y-%m-%dt%H.%M.%S"`"

# Experiment Controller Log File
EC_LOG_FILE="${OEMV_DIR}/${EXPR_ID}@EC.log"

# redirect standard error to log file
REDIR_STDERR_TO_LOGFILE="2> >(tr \"\\\"\" \"'\" | while read MSG; do echo \"<ERROR_MSG id=\\\"#\\\" at=\\\"`date +%s.%N`\\\" msg=\\\"\$MSG\\\" />\" >> $EC_LOG_FILE; done)"

# Sequence number, Message and expected Result (SMR) counter file
SMR_FILE="$TMP_DIR/SMR.txt"
echo "0 0 0" > $SMR_FILE

# COLOR definition
Black="\033[0;30m"
LRed="\033[0;31m"
DRed="\033[1;31m"
LGreen="\033[0;32m"
DGreen="\033[1;32m"
Orange="\033[0;33m"
Yellow="\033[1;33m"
LBlue="\033[0;34m"
DBlue="\033[1;34m"
LPurple="\033[0;35m"
DPurple="\033[1;35m"
LCyan="\033[0;36m"
DCyan="\033[1;36m"
LGray="\033[0;37m"
DGray="\033[1;30m"
White="\033[1;37m"
NC="\033[0m"		# No Color

