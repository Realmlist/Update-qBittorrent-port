#!/bin/bash
#Determine protonvpn port and update qBittorrent

# OBSOLETE. NOW BUILT INTO HOTIO CONTAINER
# SEE https://hotio.dev/containers/wireguard/

# Based on (read: copy-pasted from)
# https://www.reddit.com/r/ProtonVPN/comments/10owypt/successful_port_forward_on_debian_wdietpi_using/
# and
# https://github.com/soxfor/qbittorrent-natmap/blob/main/data/start.sh

QBITTORRENT_SERVER="localhost";
QBITTORRENT_PORT=8080;

LOG_FILE=/config/natpmp/port.log

if [ ! -e "$LOG_FILE" ] ; then
    mkdir -p /config/natpmp
    touch "$LOG_FILE"
fi

if [ ! -w "$LOG_FILE" ] ; then
    echo cannot write to $LOG_FILE
    exit 1
fi

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

#Function to parse the active port from the qBittorrent configuration file
findconfiguredport(){
    #grep -zoP 'Session\\Port=(\d+)' /config/config/qBittorrent.conf | tr -cd [:digit:] | xargs;
    curl -s -i "http://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}/api/v2/app/preferences" | grep -oP '(?<=\"listen_port\"\:)(\d{1,5})'
}

#Function to change the port through the qBittorrent API
qbt_changeport(){
    curl -s -i --data-urlencode "json={\"listen_port\":${current_active_port},\"random_port\":false,\"upnp\":false}" "http://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}/api/v2/app/setPreferences"
}

#Function which uses natpmp to determine the active port
findactiveport()
{
    python3 /app/natpmp/natpmp_client.py -g 10.2.0.1 0 0 | grep -oP '(?<=public port ).*(?=,)' | xargs;
}

#Execute the above functions and set variables
configured_port=$(findconfiguredport);
current_active_port=$(findactiveport);

#Determine if the port has changed from what is configured
# shellcheck disable=SC2086
if [ ${configured_port} != ${current_active_port} ]; then
    echo "------------------------------START OF RUN------------------------------";
    #Notify of port change
    echo "$(timestamp) The port has changed from ${configured_port} to ${current_active_port}";

    #If the port has changed then we should remove the allowed entry from ufw
    #echo "$(timestamp) Deleting previous allow rule from ufw: $(/usr/sbin/ufw delete allow ${configured_port})";

    #Now use qBittorrent API to update the active configuration and wait 5 seconds for the configuration to update in the background
    echo "$(timestamp) Updating qBittorrent with the new port: $(qbt_changeport).. waiting 5 seconds for configuration to update. $(sleep 5)";

    #Run function again to find the updated port in the qBittorrent configuration
    updated_configured_port=$(findconfiguredport);

        #Verify the configured port now matches the active port
        if [ ${updated_configured_port} = ${current_active_port} ]; then
            #If port is correct write out the success to the specified log file
            echo "$(timestamp) Verified port ${configured_port} was successfully updated to port ${updated_configured_port}.";
        else
            #We attempted to update qBittorrent, but the values don't match so time to panic
            echo "$(timestamp) Something went wrong.";
        fi
    echo "-------------------------------END OF RUN-------------------------------";
else
    #Nothing needs to be done because the values already match
    echo "------------------------------START OF RUN------------------------------";
    echo "$(timestamp) Configured port ${configured_port} is already correct";
    echo "-------------------------------END OF RUN-------------------------------";
fi >> $LOG_FILE
