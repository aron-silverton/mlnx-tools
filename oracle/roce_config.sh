#!/bin/bash
#
# Copyright (c) 2017, Oracle and/or its affiliates. All rights reserved.
#
# The Universal Permissive License (UPL), Version 1.0
#
# Subject to the condition set forth below, permission is hereby granted to any
# person obtaining a copy of this software, associated documentation and/or data
# (collectively the "Software"), free of charge and under any and all copyright
# rights in the Software, and any and all patent rights owned or freely
# licensable by each licensor hereunder covering either (i) the unmodified
# Software as contributed to or provided by such licensor, or (ii) the Larger
# Works (as defined below), to deal in both
#
# (a) the Software, and
# (b) any piece of software and/or hardware listed in the
#     lrgrwrks.txt file if one is included with the Software (each a "Larger
#     Work" to which the Software is contributed by such licensors),
#
# without restriction, including without limitation the rights to copy, create
# derivative works of, display, perform, and distribute the Software and make,
# use, sell, offer for sale, import, export, have made, and have sold the
# Software and the Larger Work(s), and to sublicense the foregoing rights on
# either these or other terms.
#
# This license is subject to the following condition: The above copyright notice
# and either this complete permission notice or at a minimum a reference to the
# UPL must be included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

#NETDEV is the netdev interface name (e.g.: eth4)
#IBDEV is the corresponding IB device (e.g.: mlx5_0)
#PORT is the corresponding IB port

NETDEV=""
TRUST_MODE=dscp
CC_FLAG=1
DEFAULT_TOS=32
TOS_MAP=32,32,64,96,128,160,192,192
MAJOR_VERSION=1
MINOR_VERSION=3

echo ""

print_usage() {
#Use this script to configure RoCE on Oracle setups
  echo "Usage:
	roce_config -i <netdev> [-t <trust_mode>] [-q <default_tos>] [-Q <tos_map_list>]

Options:
 -i <interface>		enter the interface name(required)

 -t <trust_mode>	set priority trust mode to pcp or dscp(default: dscp)

 -q <default_tos>	set the default tos to a value between 0-255. If this option
			is not used, default tos will remain unchanged.

 -Q <tos_map_list>      set the tos_map_N values according to the comma-seperated list
                        specified in the argument <tos_map_list>

Example:
	roce_config -i eth4 -d 0 -t pcp
"
}

print_version() {
	echo "Version: $MAJOR_VERSION.$MINOR_VERSION"
	echo ""
}

set_rocev2_default() {
	echo "RoCE v2" > /sys/kernel/config/rdma_cm/$IBDEV/ports/$PORT/default_roce_mode > /dev/null
	if [[ $? != 0 ]] ; then
		>&2 echo " - Setting RoCEv2 as rdma_cm preference failed"
		exit 1
	else
		echo " + RoCE v2 is set as default rdma_cm preference"
	fi
}

set_tos_mapping() {
	if [ ! -d "/sys/kernel/config/rdma_cm/$IBDEV/tos_map" ] ; then
		return
	fi

	(( i = 0 ))
	for mapping in ${TOS_MAP//,/ }
	do
		echo "$mapping" > /sys/kernel/config/rdma_cm/$IBDEV/tos_map/tos_map_$i
		if [[ $? != 0 ]] ; then
			>&2 echo " - Failed to set tos mapping"
			exit 1
		fi
		if (( ++i >= 8 ))
		then
			break
		fi
	done

	echo " + Tos mapping is set"
}

set_default_tos() {
	echo "$DEFAULT_TOS" > /sys/kernel/config/rdma_cm/$IBDEV/ports/$PORT/default_roce_tos
	if [[ $? != 0 ]] ; then
		>&2 echo " - Failed to set default roce tos"
		exit 1
	else
		echo " + Default roce tos is set to $DEFAULT_TOS"
	fi
}

config_trust_mode() {
	mlnx_qos -i $NETDEV --trust $TRUST_MODE > /dev/null
	if [[ $? != 0 ]] ; then
		>&2 echo " - Setting $TRUST_MODE as trust mode failed; Please make sure you installed mlnx_qos"
		exit 1
	else
		echo " + Trust mode is set to $TRUST_MODE"
	fi
}

set_cc_algo_mask() {
	yes | mstconfig -d $PCI_ADDR set ROCE_CC_PRIO_MASK_P1=255 ROCE_CC_PRIO_MASK_P2=255 \
	ROCE_CC_ALGORITHM_P1=ECN ROCE_CC_ALGORITHM_P2=ECN > /dev/null
	if [[ $? != 0 ]] ; then
		>&2 echo " - Setting congestion control algo/mask failed"
		exit 1
	fi
}

#This enables congestion control on all priorities, for RP and NP both, 
#regardless of PFC is enabled on one more priorities.
enable_congestion_control() {
	if [ -f "/sys/kernel/debug/mlx5/$PCI_ADDR/cc_params/cc_enable" ] ; then
		echo 1 > /sys/kernel/debug/mlx5/$PCI_ADDR/cc_params/cc_enable
		if [[ $? != 0 ]] ; then
			>&2 echo " - Enabling congestion control failed"
			exit 1
		else
			echo " + Congestion control enabled"
		fi
	else
		CC_VARS="$(mstconfig -d $PCI_ADDR q | grep ROCE_CC | awk '{print $NF}')"
		if [[ $? != 0 ]] ; then
			>&2 echo " - mstconfig query failed"
			exit 1
		fi
		CC_FLAG=1
		while read -r line; do
			if [[ $line != "255" && $line != "ECN(0)" ]] ; then
				CC_FLAG=0
			fi
		done <<< "$CC_VARS"
		if [[ $CC_FLAG == "1" ]] ; then
			echo " + Congestion control algo/mask are set as expected"
		else
			set_cc_algo_mask
			echo " + Congestion control algo/mask has been changed; Please **REBOOT** to load the new settings"
		fi
	fi
}

#Perform CNP frame configuration, indicating with L2 priority
#to use for sending CNP frames.
set_cnp_priority() {
	echo 7  > /sys/kernel/debug/mlx5/$PCI_ADDR/cc_params/np_cnp_prio &&
	echo 56 > /sys/kernel/debug/mlx5/$PCI_ADDR/cc_params/np_cnp_dscp
	if [[ $? != 0 ]] ; then
		>&2 echo " - Setting CNP priority lane failed"
		exit 1
	else
		echo " + CNP is set to priority lane 7"
	fi
}

if [[ $# -gt 8 || $# -lt 2 ]]
then
	print_usage
	exit 1
fi

while [ "$1" != "" ]; do
case $1 in
	-i )	shift
		NETDEV=$1
		;;
	-t )	shift
		TRUST_MODE=$1
		;;
	-q )	shift
		DEFAULT_TOS=$1
		;;
	-Q )	shift
		TOS_MAP=$1
		;;
	-v )	print_version
		exit
		;;
	-h )	print_usage
		exit
		;;
	* )	(>&2 echo " - Invalid option \"$1\"")
		print_usage
		exit 1
    esac
    shift
done

if [ "$EUID" -ne 0 ] ; then
	>&2 echo " - Please run as root"
	exit 1
fi

if [[ $NETDEV == "" ]] ; then
	>&2 echo " - Please enter an interface name, -i option is mandatory"
	print_usage
	exit 1
fi
ip a s $NETDEV > /dev/null
if [[ $? != 0 ]] ; then
	>&2 echo " - netdevice \"$NETDEV\" doesn't exist"
	exit 1
fi

IBDEV="$(ibdev2netdev | grep "$NETDEV" | head -1 | cut -f 1 -d " ")"
if [ -z "$IBDEV" ] ; then
	>&2 echo " - netdev \"$NETDEV\" doesn't have a corresponding ibdev"
	exit 1
fi
PORT="$(ibdev2netdev | grep $NETDEV | head -1 | cut -f 3 -d " ")"
echo "NETDEV=$NETDEV; IBDEV=$IBDEV; PORT=$PORT"

if [[ $TRUST_MODE != "dscp" && $TRUST_MODE != "pcp" ]] ; then
	>&2 echo " - Option -t can take only dscp or pcp as input"
	exit 1
fi

if [[ $DEFAULT_TOS -gt "255" ]] ; then
	>&2 echo " - Option -q (default tos) can only take values between 0-255"
	exit 1
fi

OS_VERSION="$(cat /etc/oracle-release | rev | cut -d" " -f1 | rev | cut -d "." -f 1)"
if [[ $OS_VERSION != "6" && $OS_VERSION != "7" ]] ; then
	>&2 echo " - Unexpected OS Version; this script works only for OL6 & OL7"
	exit 1
fi

if (! cat /proc/mounts | grep /sys/kernel/config > /dev/null) ; then
	mount -t configfs none /sys/kernel/config
	if [[ $? != 0 ]] ; then
		>&2 echo " - Failed to mount configfs"
		exit 1
	fi
fi

if [ ! -d "/sys/kernel/config/rdma_cm" ] ; then
	modprobe rdma_cm > /dev/null
	if [[ $? != 0 ]] ; then
		>&2 echo " - Failed to load rdma_cm module"
		exit 1
	fi
	if [ ! -d "/sys/kernel/config/rdma_cm" ] ; then
		>&2 echo " - rdma_cm is missing under /sys/kernel/config"
		exit 1
	fi
fi

if [ ! -d "/sys/kernel/config/rdma_cm/$IBDEV" ] ; then
	mkdir /sys/kernel/config/rdma_cm/$IBDEV
	if [[ $? != 0 ]] ; then
		>&2 echo " - Failed to create /sys/kernel/config/rdma_cm/$IBDEV"
		exit 1
	fi
fi

set_rocev2_default
set_tos_mapping
set_default_tos
config_trust_mode

PCI_ADDR="$(ethtool -i $NETDEV | grep "bus-info" | cut -f 2 -d " ")"
if [ -z "$PCI_ADDR" ] ; then
	>&2 echo " - Failed to obtain PCI ADDRESS for netdev \"$NETDEV\""
	exit 1
fi
if (! cat /proc/mounts |grep /sys/kernel/debug > /dev/null) ; then
	mount -t debugfs none /sys/kernel/debug
	if [[ $? != 0 ]] ; then
		>&2 echo " - Failed to mount debugfs"
		exit 1
	fi
fi
enable_congestion_control
set_cnp_priority

echo ""
if [[ $CC_FLAG = "0" ]] ; then
	>&2 echo "Finished configuring \"$NETDEV\", but needs a *REBOOT*"
	echo ""
	exit 1
else
	echo "Finished configuring \"$NETDEV\" ヽ(•‿•)ノ"
fi
echo ""

##################################################
##	   EXTRA CODE, PLEASE IGNORE		##
##################################################

#Set priority to traffic class configuration (optional)
#This is only needed to see if RoCEv2 traffic is really taking the right DSCP based 
#QoS when you do not have switch and want to see DSCP is in effect. This maps priority
#0 to 7 to rate limiting traffic class 0 to 7. This traffic class has nothing to do with 
#rdma_set_service_level(tos) or address_handle->sl or address_handle->traffic_class.
function ets_traffic_class_config {
	mlnx_qos -i $NETDEV -p 0,1,2,3,4,5,6,7
}

#Do ETS rate limiting (optional)
#This is only needed to see if RoCEv2 traffic is really taking the right DSCP based 
#QoS when you do not have switch and still want to see DSCP is in effect.
#(Each number below indicates maximum bw in Gbps)
function ets_rate_limiting {
	mlnx_qos -i $NETDEV -r 5,4,3,2,1,10,17,8
}
#	lldptool -T -i $NETDEV -V sysCap enableTx=yes
#	lldptool -T -i $NETDEV -V mngAddr enableTx=yes
#	lldptool -T -i $NETDEV -V PFC enableTx=yes
#	lldptool -T -i $NETDEV -V CEE-DCBX enableTx=yes
#	lldptool set-lldp -i $NETDEV adminStatus=rxtx
