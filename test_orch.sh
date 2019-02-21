#!/bin/bash

# Install the linux standard base (lsb) release package
if ! dpkg -l | grep "ii  lsb-release " > /dev/null; then
	echo -e "${Orange}INFO${NC}: Installing lsb_release on EC ..."
	sudo apt-get -y install lsb-release
fi
# Make sure EC's OS is either Debian or Ubuntu
dstrn_ID=$(lsb_release -i | cut -d: -f 2 | tr -d [:blank:])
if [[ "$dstrn_ID" != "Debian" ]] && [[ "$dstrn_ID" != "Ubuntu" ]]; then
	echo -e "${LRed}ERROR${NC}: EC should only be either Debian or Ubuntu distrbution"
	exit
fi

# ----------------------------------------------------------------------------------------- #
# Check for installed programs on EC node
EC_exec_name=( "ifconfig"  "nc"             "bc" "curl" "rpcbind" "ptpd" "xargs"     )
EC_apt_name=(  "net-tools" "netcat-openbsd" "bc" "curl" "rpcbind" "ptpd" "findutils" )
for (( i = 0 ; i < ${#EC_apt_name[@]} ; i++ )) do
	if ! dpkg -l | grep "ii  ${EC_apt_name[$i]} " > /dev/null; then
		echo -e "${Orange}INFO${NC}: Installing ${EC_exec_name[$i]} on EC ..."
		sudo apt-get -y install ${EC_apt_name[$i]}
	fi
done

# Make sure we are not working inside a docker container
if [ ! -f /.dockerenv ]; then

	# Check for nfs server program
	if ! dpkg -l | grep "ii  nfs-kernel-server " > /dev/null; then
		echo -e "${LRed}ERROR${NC}: Install nfs-kernel-server tool on EC. After installation, issue the following commands"
		echo "sudo su"
		echo "echo \"$BEOF_DIR/tmp *(rw,sync,no_root_squash,no_subtree_check)\" >> /etc/exports"
		echo "echo \"$BEOF_DIR/config *(rw,sync,no_root_squash,no_subtree_check)\" >> /etc/exports"
		echo "echo \"$BEOF_DIR/exec *(rw,sync,no_root_squash,no_subtree_check)\" >> /etc/exports"
		echo "exportfs -rav"
		echo "service nfs-kernel-server restart"
		exit
	fi
	# Make sure EC [tmp, config and exec] directories are NFS exported
	exported_DIRs=( $(cat /var/lib/nfs/etab | cut -d$'\t' -f1) )
	if ! $(elementExists "$BEOF_DIR/tmp" exported_DIRs) ; then
		echo -e "${LRed}ERROR${NC}: $BEOF_DIR/tmp directory is not NFS exported. Issue the following commands to export it"
		echo "sudo su"
		echo "echo \"$BEOF_DIR/tmp *(rw,sync,no_root_squash,no_subtree_check)\" >> /etc/exports"
		echo "exportfs -rav"
		echo "service nfs-kernel-server restart"
		exit
	fi
	if ! $(elementExists "$BEOF_DIR/config" exported_DIRs) ; then
		echo -e "${LRed}ERROR${NC}: $BEOF_DIR/config directory is not NFS exported. Issue the following commands to export it"
		echo "sudo su"
		echo "echo \"$BEOF_DIR/config *(rw,sync,no_root_squash,no_subtree_check)\" >> /etc/exports"
		echo "exportfs -rav"
		echo "service nfs-kernel-server restart"
		exit
	fi
	if ! $(elementExists "$BEOF_DIR/exec" exported_DIRs) ; then
		echo -e "${LRed}ERROR${NC}: $BEOF_DIR/exec directory is not NFS exported. Issue the following commands to export it"
		echo "sudo su"
		echo "echo \"$BEOF_DIR/exec *(rw,sync,no_root_squash,no_subtree_check)\" >> /etc/exports"
		echo "exportfs -rav"
		echo "service nfs-kernel-server restart"
		exit
	fi

fi

# ----------------------------------------------------------------------------------------- #
# Check for installed programs on RC node
echo -e "${Orange}INFO${NC}: Checking for installed packages on all nodes ..."

# Common executables
common_exec_name=( "ifconfig"  "killall" "bc" "ptpd" "mount" "mountpoint"  "find"      "xargs"     "nfs-common" "brctl" )
common_apt_name=(  "net-tools" "psmisc"  "bc" "ptpd" "mount" "initscripts" "findutils" "findutils" "nfs-common" "bridge-utils" )
common_exec_str="printf \"#\\041/bin/bash\\nOrange=\\\"\\\\\\033[0;33m\\\"\\nNC=\\\"\\\\\\033[0m\\\"\\ncommon_exec_name=( ${common_exec_name[*]} )\\ncommon_apt_name=( ${common_apt_name[*]} )\\nfor (( i = 0 ; i < \${#common_exec_name[@]} ; i++ )) do\\n\\tif ! dpkg -l | grep \\\"ii\\040\\040\${common_apt_name[\$i]} \\\" > /dev/null; then\\n\\t\\techo -e \\\"\${Orange}INFO\${NC}: Installing \${common_exec_name[\$i]} ...\\\"\\n\\t\\tsudo apt-get -y install \${common_apt_name[\$i]}\\n\\tfi\\ndone\""
exec_WR ${GROUP_ALL[MCT_ADDR]} "$common_exec_str > /tmp/common_exec.sh && chmod a+x /tmp/common_exec.sh && /tmp/common_exec.sh && rm /tmp/common_exec.sh"

# Wi-Fi executables
if [[ -v "${GROUP_ALL_WIFI}" ]]; then
	WIFI_exec_name=( "iw" "hostapd" "wpa_supplicant" )
	WIFI_apt_name=(  "iw" "hostapd" "wpasupplicant"  )
	WIFI_exec_str="printf \"#\\041/bin/bash\\nOrange=\\\"\\\\\\033[0;33m\\\"\\nNC=\\\"\\\\\\033[0m\\\"\\nWIFI_exec_name=( ${WIFI_exec_name[*]} )\\nWIFI_apt_name=( ${WIFI_apt_name[*]} )\\nfor (( i = 0 ; i < \${#WIFI_exec_name[@]} ; i++ )) do\\n\\tif ! dpkg -l | grep \\\"ii\\040\\040\${WIFI_apt_name[\$i]} \\\" > /dev/null; then\\n\\t\\techo -e \\\"\${Orange}INFO\${NC}: Installing \${WIFI_exec_name[\$i]} ...\\\"\\n\\t\\tsudo apt-get -y install \${WIFI_apt_name[\$i]}\\n\\tfi\\ndone\""
	exec_WR ${GROUP_ALL_WIFI[MCT_ADDR]} "$WIFI_exec_str > /tmp/WIFI_exec.sh && chmod a+x /tmp/WIFI_exec.sh && /tmp/WIFI_exec.sh && rm /tmp/WIFI_exec.sh"
fi

# Bluetooth executables
if [[ -v "${GROUP_ALL_BT}" ]]; then
	BT_exec_name=( "hciconfig" "pand"         )
	BT_apt_name=(  "bluez"     "bluez-compat" )
	BT_exec_str="printf \"#\\041/bin/bash\\nOrange=\\\"\\\\\\033[0;33m\\\"\\nNC=\\\"\\\\\\033[0m\\\"\\nBT_exec_name=( ${BT_exec_name[*]} )\\nBT_apt_name=( ${BT_apt_name[*]} )\\nfor (( i = 0 ; i < \${#BT_exec_name[@]} ; i++ )) do\\n\\tif ! dpkg -l | grep \\\"ii\\040\\040\${BT_apt_name[\$i]} \\\" > /dev/null; then\\n\\t\\techo -e \\\"\${Orange}INFO\${NC}: Installing \${BT_exec_name[\$i]} ...\\\"\\n\\t\\tsudo apt-get -y install \${BT_apt_name[\$i]}\\n\\tfi\\ndone\""
	exec_WR ${GROUP_ALL_BT[MCT_ADDR]} "$BT_exec_str > /tmp/BT_exec.sh && chmod a+x /tmp/BT_exec.sh && /tmp/BT_exec.sh && rm /tmp/BT_exec.sh"
fi

# ----------------------------------------------------------------------------------------- #
# Check if EC directories [temp, config and exec] exist and create them if they don't
exec_WR ${GROUP_ALL[MCT_ADDR]} "mkdir -p $BEOF_DIR/tmp $BEOF_DIR/config $BEOF_DIR/exec"

# Mount EC directories on RC nodes
echo -e "${Orange}INFO${NC}: Mounting EC directories [tmp, config and exec] on all nodes ..."
exec_WR ${GROUP_ALL[MCT_ADDR]} "if ! mountpoint -q $BEOF_DIR/tmp;	then sudo mount -t nfs $HOST_EC:$BEOF_DIR/tmp    $BEOF_DIR/tmp;    fi"
exec_WR ${GROUP_ALL[MCT_ADDR]} "if ! mountpoint -q $BEOF_DIR/config;	then sudo mount -t nfs $HOST_EC:$BEOF_DIR/config $BEOF_DIR/config; fi"
exec_WR ${GROUP_ALL[MCT_ADDR]} "if ! mountpoint -q $BEOF_DIR/exec;	then sudo mount -t nfs $HOST_EC:$BEOF_DIR/exec   $BEOF_DIR/exec;   fi"

# ----------------------------------------------------------------------------------------- #


