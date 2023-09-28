	#!/usr/bin/env bash

# Define target network chain ID
CHAIN_ID="aya_preview_501"

# Define NODE1 details (sentry1)
AYA_HOST1="peer1-501.worldmobilelabs.com"
AYA_URL1="http://$AYA_HOST1"
AYA_P2P_PORT1=26656
AYA_RPC_PORT1=26657

# Define NODE2 details (sentry2)
AYA_HOST2="peer2-501.worldmobilelabs.com"
AYA_URL2="http://$AYA_HOST2"
AYA_P2P_PORT2=26656
AYA_RPC_PORT2=26657

# Define NODE3 details (seeder1)
AYA_HOST3="peer3-501.worldmobilelabs.com"
AYA_URL3="http://$AYA_HOST3"
AYA_P2P_PORT3=26656
AYA_RPC_PORT3=26657


# This function execute command with sudo if user not root
sudo () {
  [[ $EUID = 0 ]] || set -- command sudo "$@"
  "$@"
}

# This function displays usage instructions for the script
usage() {
  # Display Usage
  echo "Usage:"
  echo "Syntax: install_sentry.sh -m <nodeMoniker>"
  echo "options:"
  echo "m     Set the Sentry Node Moniker."
  echo
}

# This function displays a message to contact support and exits the script
contact_support() {
  echo "Please contact support."
  exit 1
}

# This function stop cosmovisor and remove installation directory
install_cleanup() {
  echo "Installation cleanup."
  pkill cosmovisor >/dev/null 2>&1
  rm -rf "${aya_home}" >/dev/null 2>&1
}


# Show welcome message

echo "****************************************************************************"
echo "NODEX Services Aya Testnet \"$CHAIN_ID\" Sentry Node Installation Script"
echo "****************************************************************************"

# Set the path to the aya home directory
aya_home=/opt/aya

# Set the path to the current script
path=$(realpath "${BASH_SOURCE:-$0}")

# Set the path to the logfile using the current timestamp
logfile=$(dirname "${path}")/installation_$(date +%s).log

# Set the path to the cosmovisor logfile
cosmovisor_logfile=${aya_home}/logs/cosmovisor.log

# Set the path to the json file with validator registration data
sentry_json=${aya_home}/sentry.json

# Clear the contents of the logfile
true >"$logfile"

## If the 'jq' package is not installed, install it
if ! dpkg -s jq >/dev/null 2>&1; then
  echo -e "-- Installing dependencies (jq package)\n"
  sudo apt-get -q install jq -y >/dev/null 2>&1
fi

# Check the checksum of the 'ayad' binary against the 'release_checksums' file
# If the checksums do not match, exit the script with an error message
grep "$(sha256sum ayad)" release_checksums 1>/dev/null
if [[ $? -ne 0 ]]; then
  echo "Incorrect checksum of ayad binary"
  exit 1
fi

# Check the checksum of the 'cosmovisor' binary against the 'release_checksums' file
# If the checksums do not match, exit the script with an error message
grep "$(sha256sum cosmovisor)" release_checksums 1>/dev/null
if [[ $? -ne 0 ]]; then
  echo "Incorrect checksum of cosmovisor binary"
  exit 2
fi


# Initialize empty variables for the node moniker
moniker=''

# Parse the command-line options passed to the script
# Set the value of the 'moniker' variable with the 'm' flag
while getopts 'm:v' flag; do
  case "${flag}" in
  m) moniker="${OPTARG}" ;;
  *)
    usage
    exit 1
    ;;
  esac
done

# If the 'moniker' or  variables are empty, display an error message and the usage before exiting the script
if [[ ! "$moniker" ]] ; then
  echo "Arguments  -m must be provided"
  usage
  exit 1
fi

# Check for previous installation traces
# If present then ask user what to do: try to continue synchronization, start from scratch or cancel
if [[ -d "$aya_home" ]]; then
  echo "Your system already contains an installation directory."
  echo "If you had problems with the installation then you have the following options:"
  echo "- [restart(R)] - erase all existing data and start from scratch"
  echo "- [cancel(C)] - cancel installation"
  echo " WARNING: Erasing wil remove all installation without recovery!"
  echo " Make sure you backed up important files before doing so."
  while true; do
      read -p "What's your choice? [restart(R)/cancel(C)]: " answer
      case $answer in
          [Rr]* ) install_cleanup; break;;
          [Cc]* ) exit;;
          * ) echo "Please answer [restart(R)/cancel(C)].";;
      esac
  done
fi

echo ""
echo "The following configuration will be used:"
echo ""
echo "RPC snapshot:"
echo "-------------"
echo "RPC_RELAY1 ${AYA_HOST1}:${AYA_RPC_PORT1}"
echo "RPC_RELAY2 ${AYA_HOST2}:${AYA_RPC_PORT2}"
echo ""
echo "P2P seeder:"
echo "-----------"
echo "RPC_RELAY1 ${AYA_HOST3}:${AYA_P2P_PORT3}"
echo ""
echo "P2P persistent peers"
echo "--------------------"
echo "RPC_RELAY1 ${AYA_HOST1}:${AYA_P2P_PORT1}"
echo "RPC_RELAY2 ${AYA_HOST2}:${AYA_P2P_PORT2}"
echo ""

read -r -p "Do you want to continue? [y/N] " response
if ! [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  exit
fi

echo "Creating installation directory ${aya_home} ..."

# Create the necessary directories
sudo mkdir -p $aya_home
sudo chown "${USER}:${USER}" $aya_home
mkdir -p "${aya_home}"/cosmovisor/genesis/bin
mkdir -p "${aya_home}"/backup
mkdir -p "${aya_home}"/logs
mkdir -p "${aya_home}"/config


# Copy 'ayad' and 'cosmovisor' binaries the the appropriate directories. Suppress shell output.
cp ayad "${aya_home}"/cosmovisor/genesis/bin/ayad >/dev/null 2>&1
cp cosmovisor "${aya_home}"/cosmovisor/cosmovisor >/dev/null 2>&1

echo "Initializing the sentry node ${moniker} ..."
# Initialize the node with the specified 'moniker'
# If this fails, display an error message and call the 'contact_support()' function to exit
if ! ./ayad init "${moniker}" --chain-id $CHAIN_ID --home ${aya_home} >"$logfile" 2>&1; then
  echo "Failed to initialize the node "
  contact_support
fi

echo "Preparing the snapshot..."

# Copy the 'genesis.json' file to the 'config' directory
cp genesis.json "${aya_home}"/config/genesis.json

# Value equal to snapshot creation interval
INTERVAL=100

# Get latest block height on chain
LATEST_HEIGHT=$(curl -s "${AYA_URL1}:${AYA_RPC_PORT1}/block" | jq -r .result.block.header.height)
if [ -z "${LATEST_HEIGHT}" ]; then
  echo "Failed to query latest block height over RPC request."
  contact_support
fi
# Get a bit older block height, to validate snapshot over it
BLOCK_HEIGHT=$((($((LATEST_HEIGHT / INTERVAL)) - 1) * INTERVAL + $((INTERVAL / 2))))
# Get block hash for "safe" block height
TRUST_HASH=$(curl -s "${AYA_URL1}:${AYA_RPC_PORT1}/block?height=${BLOCK_HEIGHT}" | jq -r .result.block_id.hash)
if [ -z "${TRUST_HASH}" ]; then
  echo "Failed to query trusted block hash over RPC request."
  contact_support
fi

echo "Snapshot will start at block height ${BLOCK_HEIGHT} with interval ${INTERVAL}"

# Enable StateSync module, to speed up node initial bootstrap
sed -i -E "s|^(enable[[:space:]]+=[[:space:]]+).*$|\1true|" "${aya_home}"/config/config.toml
# Set available RPC servers (at least two) required for light client snapshot verification
sed -i -E "s|^(rpc_servers[[:space:]]+=[[:space:]]+).*$|\1\"${AYA_URL1}:${AYA_RPC_PORT1},${AYA_URL2}:${AYA_RPC_PORT2}\"|" "${aya_home}"/config/config.toml
# Set "safe" trusted block height
sed -i -E "s|^(trust_height[[:space:]]+=[[:space:]]+).*$|\1$BLOCK_HEIGHT|" "${aya_home}"/config/config.toml
# Set "safe" trusted block hash
sed -i -E "s|^(trust_hash[[:space:]]+=[[:space:]]+).*$|\1\"$TRUST_HASH\"|" "${aya_home}"/config/config.toml
# Set trust period, should be ~2/3 unbonding time (3 weeks for preview network)
sed -i -E "s|^(trust_period[[:space:]]+=[[:space:]]+).*$|\1\"302h0m0s\"|" "${aya_home}"/config/config.toml

# Temporary fix for https://github.com/cosmos/cosmos-sdk/issues/13766, will be removed after binary rebuild over Cosmos SDK v0.46.7 or above
# Set snapshot interval >0 to activate snapshot manager
sed -i -E 's|^(snapshot-interval[[:space:]]+=[[:space:]]+).*$|\1999999999999|' ${aya_home}/config/app.toml

# Set the log level to 'error' in the 'config.toml' file
sed -i "s/log_level = \"info\"/log_level = \"error\"/g" "${aya_home}"/config/config.toml

# Get AYA NODE1 ID
AYA_NODE1_ID=$(curl -s "${AYA_URL1}:${AYA_RPC_PORT1}/status" | jq -r .result.node_info.id)
if [ -z "${AYA_NODE1_ID}" ]; then
  echo "Failed to query AYA NODE1 ID over RPC request."
  contact_support
fi

# Get AYA NODE2 ID
AYA_NODE2_ID=$(curl -s "${AYA_URL2}:${AYA_RPC_PORT2}/status" | jq -r .result.node_info.id)
if [ -z "${AYA_NODE2_ID}" ]; then
  echo "Failed to query AYA NODE2 ID over RPC request."
  contact_support
fi

# Get AYA NODE3 ID
AYA_NODE3_ID=$(curl -s "${AYA_URL3}:${AYA_RPC_PORT3}/status" | jq -r .result.node_info.id)
if [ -z "${AYA_NODE3_ID}" ]; then
  echo "Failed to query AYA NODE3 ID over RPC request."
  contact_support
fi

# Set the seed nodes in the 'config.toml' file
sed -i -E "s|^(seeds[[:space:]]+=[[:space:]]+).*$|\1\"${AYA_NODE3_ID}@${AYA_HOST3}:${AYA_P2P_PORT3}\"|" "${aya_home}"/config/config.toml

# Set the seed nodes in the 'config.toml' file
sed -i -E "s|^(persistent_peers[[:space:]]+=[[:space:]]+).*$|\1\"${AYA_NODE1_ID}@${AYA_HOST1}:${AYA_P2P_PORT1},${AYA_NODE2_ID}@${AYA_HOST2}:${AYA_P2P_PORT2}\"|" "${aya_home}"/config/config.toml

# Replace GRPC port to not overlap with standard Prometheus port
sed -i "s/:9090/:29090/g" "${aya_home}"/config/app.toml

# Change gas price units for our network
sed -i 's/0stake/0uswmt/g' "${aya_home}"/config/app.toml

# Export some environment variables
export DAEMON_NAME=ayad
export DAEMON_HOME="${aya_home}"
export DAEMON_DATA_BACKUP_DIR="${aya_home}"/backup
export DAEMON_RESTART_AFTER_UPGRADE=true
export DAEMON_ALLOW_DOWNLOAD_BINARIES=true

# Set soft file descriptors limit for session (default: 1024)
ulimit -Sn 4096

echo "Starting cosmovisor to start the snapshot process. You can check logs at ${cosmovisor_logfile}"

# Start 'cosmovisor'. Append output to log file. Run in the background so script can continue.
"${aya_home}"/cosmovisor/cosmovisor run start --home ${aya_home} &>>"${cosmovisor_logfile}" &

# Verify 'cosmovisor' process is running.
# If its not running display status in terminal and log file. Proceed to call 'contact_support()' function.
if ! pgrep cosmovisor >/dev/null 2>&1; then
  echo "Cosmovisor not running." | tee -a "$logfile"
  contact_support
fi

# Get the address of the validator
validator_address=$(./ayad tendermint show-address --home ${aya_home})
# Use 'jq' to create a JSON object with the 'moniker', 'operator_address' and 'validator_address' fields
jq --arg key0 'moniker' \
  --arg value0 "$moniker" \
  --arg key1 'validator_address' \
  --arg value1 "$validator_address" \
  '. | .[$key0]=$value0 | .[$key1]=$value1'  \
  <<<'{}' | tee $sentry_json

echo -e "\n-- Now we have to wait until your node is up to date... It will take a while!\n"

# Sleep for 30 seconds
sleep 30

# Set authorized to false
authorized=false

# While authorized is false, do the following:
while [ "$authorized" = "false" ]; do
   # Get node status
   node_status=$(./ayad status --home ${aya_home})

   #get catching up 
   catching_up=$(echo "$node_status"| jq '.SyncInfo.catching_up' | sed 's/"//g')

   if [ $catching_up = false ]; then
     authorized=true
   else 
    # Get first chain block time
    chain_first_block_time=$(echo "$node_status"| jq '.SyncInfo.earliest_block_time' | sed 's/"//g')
    # Get last received block time
    chain_current_block_time=$(echo "$node_status"| jq '.SyncInfo.latest_block_time' | sed 's/"//g')
    # Get last received block height
    chain_current_block_height=$(echo "$node_status" | jq '.SyncInfo.latest_block_height' | sed 's/"//g')
    # Calculate current chain state age in seconds
    chain_current_age=$(( $(date +%s -d "$chain_current_block_time") - $(date +%s -d "$chain_first_block_time") ))
    # Calculate chain age up to now in seconds
    chain_full_age=$(( $(date +%s) - $(date +%s -d "$chain_first_block_time") ))
    # Calculate chain relative synchronization progress
    sync_progress=$((100*100*chain_current_age/chain_full_age))
    # Correct synchronization progress edge case for start
    if [ "$sync_progress" -eq "0" ]; then sync_progress="0000"; fi
    # If the balance of the operator address not contain 'uswmt' denomination, print a message and sleep for 60 seconds
    echo -e "\e[1A\e[K Still syncing... Progress: ${sync_progress:0:-2}.${sync_progress: -2}% Height: ${chain_current_block_height} Last update: $(date)"
    sleep 10
  fi
done
# Remove temporary fix for https://github.com/cosmos/cosmos-sdk/issues/13766
# Set snapshot interval back to default (0) after installation
sed -i -E 's|^(snapshot-interval[[:space:]]+=[[:space:]]+).*$|\1100|' ${aya_home}/config/app.toml

# Disable StateSync module to avoid possible problems on node restart
sed -i -E "s|^(enable[[:space:]]+=[[:space:]]+).*$|\1false|" "${aya_home}"/config/config.toml

echo -e "\n-- All up to date! You can now connect your validator node to this sentry!\n"

echo -e "\n-- Welcome to Aya sidechain :D \n\n"

echo -e "-- Configuring your node to start on server startup\n"

# Create symbolic links for the 'ayad' and 'cosmovisor' binaries
sudo ln -s $aya_home/cosmovisor/current/bin/ayad /usr/local/bin/ayad >/dev/null 2>&1
sudo ln -s $aya_home/cosmovisor/cosmovisor /usr/local/bin/cosmovisor >/dev/null 2>&1

# Create systemd service file that describes the background service running the 'cosmovisor' daemon.
sudo tee /etc/systemd/system/cosmovisor.service > /dev/null <<EOF
# Start the 'cosmovisor' daemon and append any output to the 'aya.log' file
# Create a Systemd service file for the 'cosmovisor' daemon
[Unit]
Description=Aya Node
After=network-online.target

[Service]
User=$USER
# Start the 'cosmovisor' daemon with the 'run start' command and write output to 'aya.log' file
ExecStart=$(which cosmovisor) run start --home "${aya_home}" "
# Restart the service if it fails
Restart=always
# Restart the service after 3 seconds if it fails
RestartSec=3
# Set the maximum number of file descriptors
LimitNOFILE=4096

# Set environment variables for data backups, automatic downloading of binaries, and automatic restarts after upgrades
Environment="DAEMON_NAME=ayad"
Environment="DAEMON_HOME=${aya_home}"
Environment="DAEMON_DATA_BACKUP_DIR=${aya_home}/backup"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=true"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"

[Install]
# Start the service on system boot
WantedBy=multi-user.target
EOF


# Reload the Systemd daemon
sudo systemctl daemon-reload

# Enable the 'cosmovisor' service to start on system boot
sudo systemctl enable cosmovisor
sudo systemctl stop cosmovisor
sudo systemctl start cosmovisor





