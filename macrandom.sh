#!/bin/bash                                                                                                                         
# MAC address randomization script
# Based on: https://forums.puri.sm/t/mac-address-randomization-script/11060
# Written by: P
# file: macrandom.sh , usage: macrandom.sh DEVICE

# -------------------- Verifications ------------------------                                                                       
[ "$1" == "" ] && echo -e "\e[1;31mSyntax error\e[0m: $0 <link-name-from-ifconfig-or-ip>" && exit 1
device=$1

SUDO=""
if [ "$(whoami)" != "root" ] ; then
    which sudo >/dev/null
    [ $? -ne 0 ] && echo -e "\e[1;31mError\e[0m: 'sudo' is required, or execute in root" && exit 1
    SUDO="sudo"
fi

# Is ifconfig available ?                                                                                                           
flg_ifconfig=0
which ifconfig >/dev/null
[ $? -eq 0 ] && flg_ifconfig=1

# Is ip available ?                                                                                                                 
flg_ip=0
which ip >/dev/null
[ $? -eq 0 ] && flg_ip=1

[ ${flg_ifconfig} -ne 1 ] && [ ${flg_ip} -ne 1 ] && echo -e "\e[1;31mError\e[0m: 'ifconfig' or 'ip' command is required" && exit 1

# -------------------- Initialisations ------------------------                                                                     
# Manufacturer table IDs                                                                                                            
declare -a manu_table=(
"78:54:2e" #(d-link)                                                                                                                
"48:af:72" #(intel)                                                                                                                 
"48:5d:60" #(broadcom - AzureWave Technology)                                                                                       
"08:d4:0c" #(intel)                                                                                                                 
"0c:7a:15" #(intel)                                                                                                                 
# Add your known 3 first bytes of WIFI cards                                                                                        
)
nb_id=${#manu_table[@]}

# Get 6 random hexa from uuidgen for the last 3 bytes of the MAC                                                                    
mac=$(uuidgen -r)

# Random choos of the manufacturer                                                                                                  
id_manu=$(( $RANDOM % ${nb_id} ))

mac="${manu_table[${id_manu}]}:${mac:0:2}:${mac:2:2}:${mac:4:2}"

# -------------------- Setting the MAC ------------------------                                                                     
flg_ok=0
while [ $flg_ok -ne 1 ] ; do
    # Priority on 'ip', because 'ifconfig' is being replaced                                                                        
    if [ ${flg_ip} -eq 1 ] ; then
        ${SUDO} ip link set dev ${device} down
        ${SUDO} ip link set ${device} address ${mac}
        ${SUDO} ip link set dev ${device} up
    else
        ${SUDO} ifconfig ${device} down
        ${SUDO} ifconfig ${device} hw ether ${mac}
        ${SUDO} ifconfig ${device} up
    fi

    # Verify with ifconfig                                                                                                          
    if [ ${flg_ifconfig} -eq 1 ] ; then
        current_mac=$(ifconfig ${device} | grep -m1 ether | awk '{ print $2 }')
        [ "${current_mac}" == "${mac}" ] && flg_ok=1
    fi

    # Verify with ip                                                                                                                
    if [ ${flg_ip} -eq 1 ] ; then
        current_mac=$(ip link | grep -m1 ${device} -A1 | grep -m1 ether | awk '{ print $2 }')
        [ "${current_mac}" == "${mac}" ] && flg_ok=1
    fi
done

echo "New MAC : '${mac}'"

exit 0
