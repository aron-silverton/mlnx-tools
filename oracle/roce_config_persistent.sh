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

# NETDEV is the netdev interface name (e.g.: eth4)
# W_DCBX identifies if dynamic/static config is preferred

NETDEV=""
IPADDR=""
W_DCBX=1
PFC_STRING=1,2,3,4,5,6

print_usage() {
#Use this script to configure RoCE on Oracle setups
  echo "Usage:
        roce_config_persistent -i <netdev> -a <ipaddr> [-d <n>] [-p <pfc_string>]

Options:
 -i <interface>         enter the interface name(required)

 -a <ipaddr>		enter the ip address(required)

 -d <n>                 n is 1 if dynamic config(DCBX)is preferred,
                          is 0 if static config is preferred (default: 1)

 -p <pfc_string>        enter the string of priority lanes to enable pfc for them
                        (default: 1,2,3,4,5,6). This is ignored for dynamic config.

Example:
        roce_config_persistent -i eth4 -a 192.168.10.67 -d 0
"
}

start_lldpad() {
        if [[ $OS_VERSION == "6" ]] ; then
                service lldpad start > /dev/null
        else
                /bin/systemctl start lldpad.service > /dev/null
        fi
        if [[ $? != 0 ]] ; then
                >&2 echo " - Starting lldpad failed; exiting"
                exit 1
        else
                echo " + Service lldpad is running"
        fi
}

#This generic lldpad configuration(not related to RoCE)
do_lldpad_config() {
        lldptool set-lldp -i $NETDEV adminStatus=rxtx > /dev/null &&
        lldptool -T -i $NETDEV -V sysName enableTx=yes > /dev/null &&
        lldptool -T -i $NETDEV -V portDesc enableTx=yes > /dev/null &&
        lldptool -T -i $NETDEV -V sysDesc enableTx=yes > /dev/null &&
        lldptool -T -i $NETDEV -V sysCap enableTx=yes > /dev/null &&
        lldptool -T -i $NETDEV -V mngAddr enableTx=yes ipv4=$IPADDR > /dev/null
        if [[ $? != 0 ]] ; then
                >&2 echo " - Generic lldpad configuration failed"
                exit 1
        else
                echo " + Finished generic lldpad configuration"
        fi
}

config_pfc() {
#Alternatively pfc config could be done by using mlnx_qos tool
#       mlnx_qos -i $NETDEV --pfc 0,1,1,1,1,1,1,0

        lldptool -T -i $NETDEV -V PFC enableTx=yes > /dev/null &&
        lldptool -T -i $NETDEV -V PFC willing=no > /dev/null &&
        lldptool -T -i $NETDEV -V PFC enabled=$PFC_STRING > /dev/null
        if [[ $? != 0 ]] ; then
                >&2 echo " - Configuring PFC failed for priority lanes $PFC_STRING"
                exit 1
        else
                echo " + PFC is configured for priority lanes $PFC_STRING"
        fi
}

enable_pfc_willing() {
        lldptool -T -i $NETDEV -V PFC enableTx=yes > /dev/null &&
        lldptool -T -i $NETDEV -V PFC willing=yes > /dev/null
        if [[ $? != 0 ]] ; then
                >&2 echo " - Enabling PFC willing bit failed"
                exit 1
        else
                echo " + Enabled PFC willing bit"
        fi
}

OS_VERSION="$(cat /etc/oracle-release | rev | cut -d" " -f1 | rev | cut -d "." -f 1)"
if [[ $OS_VERSION != "6" && $OS_VERSION != "7" ]] ; then
        >&2 echo " - Unexpected OS Version; this script works only for OL6 & OL7"
        exit 1
fi

if [[ $# -gt 8 ]]
then
        print_usage
        exit 1
fi

while [ "$1" != "" ]; do
case $1 in
        -i )    shift
                NETDEV=$1
                ;;
        -d )    shift
                W_DCBX=$1
                ;;
        -p )    shift
                PFC_STRING=$1
                ;;
	-a )	shift
		IPADDR=$1
		;;
        -h )    print_usage
                exit
                ;;
        * )     (>&2 echo " - Invalid option \"$1\"")
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

if [[ $IPADDR == "" ]] ; then
        >&2 echo " - Please enter an ip address, -a option is mandatory"
        print_usage
        exit 1
fi


if [[ $W_DCBX != "1" && $W_DCBX != "0" ]] ; then
        >&2 echo " - Option -d can take only 1 or 0 as input"
        exit 1
fi

start_lldpad
do_lldpad_config
if [[ $W_DCBX == "0" ]] ; then
        config_pfc
else
        enable_pfc_willing
fi

echo ""
echo "Finished configuring \"$NETDEV\" ヽ(•‿•)ノ"
echo ""

