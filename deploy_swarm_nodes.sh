#!/bin/bash

# --- Configuration ---
# IMPORTANT: Replace with the actual absolute path to your project's root directory on the COORDINATOR
COORDINATOR_PROJECT_ROOT_PATH="/home/youruser/your-project" # Example: /home/ubuntu/my-blockchain-swarm

# IMPORTANT: Replace with the actual absolute path to your project's root directory on the SWARM NODES
SWARM_NODE_PROJECT_ROOT_PATH="/home/youruser/your-project" # Example: /home/ubuntu/my-blockchain-swarm

# IMPORTANT: Replace with the SSH username for your Swarm Node Runner devices
SWARM_NODE_SSH_USER="youruser" # Example: ubuntu, ec2-user

# IMPORTANT: List the IP addresses of all your Swarm Node Runner devices
SWARM_NODE_IPS=("SWARM_NODE_IP_1" "SWARM_NODE_IP_2") # Example: ("192.168.1.101" "192.168.1.102")

# Get the Coordinator Device's IP (same logic as in deploy_coordinator.sh)
COORDINATOR_DEVICE_IP=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
if [ -z "$COORDINATOR_DEVICE_IP" ]; then
    COORDINATOR_DEVICE_IP=$(ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
fi

if [ -z "$COORDINATOR_DEVICE_IP" ]; then
    echo "ERROR: Could not determine Coordinator Device IP. Please ensure deploy_coordinator.sh ran successfully."
    exit 1
fi

echo "--- Starting Swarm Node Runners Deployment ---"
echo "Coordinator IP for nodes: ${COORDINATOR_DEVICE_IP}"
echo "Target Swarm Node IPs: ${SWARM_NODE_IPS[*]}"

# --- Loop through each Swarm Node ---
NODE_COUNTER=1
for NODE_IP in "${SWARM_NODE_IPS[@]}"; do
    NODE_ID="node${NODE_COUNTER}" # Assign a unique NODE_ID for each runner
    echo ""
    echo "--- Deploying Swarm Node Runner: ${NODE_IP} (ID: ${NODE_ID}) ---"

    # --- 1. Initial Project Setup on Swarm Node ---
    echo "1. Pulling latest code on ${NODE_IP}..."
    ssh "${SWARM_NODE_SSH_USER}@${NODE_IP}" "cd ${SWARM_NODE_PROJECT_ROOT_PATH} && git pull origin main" || { echo "ERROR: Failed to pull Git repository on ${NODE_IP}. Skipping this node."; NODE_COUNTER=$((NODE_COUNTER+1)); continue; }

    # --- 2. Create Crypto Dirs on Swarm Node (if they don't exist) ---
    echo "2. Creating necessary crypto directories on ${NODE_IP}..."
    ssh "${SWARM_NODE_SSH_USER}@${NODE_IP}" "
        mkdir -p ${SWARM_NODE_PROJECT_ROOT_PATH}/fabric-network/crypto-config/peerOrganizations/techcombank.example.com/users/Admin@techcombank.example.com/
        mkdir -p ${SWARM_NODE_PROJECT_ROOT_PATH}/fabric-network/crypto-config/peerOrganizations/techcombank.example.com/peers/peer0.techcombank.example.com/tls/
        mkdir -p ${SWARM_NODE_PROJECT_ROOT_PATH}/fabric-network/crypto-config/ordererOrganizations/example.com/orderers/orderer.example.com/tls/
    " || { echo "ERROR: Failed to create crypto directories on ${NODE_IP}. Skipping this node."; NODE_COUNTER=$((NODE_COUNTER+1)); continue; }

    # --- 3. Copy Fabric Crypto Material to Swarm Node ---
    echo "3. Copying Fabric crypto material to ${NODE_IP}..."
    scp -r "${COORDINATOR_PROJECT_ROOT_PATH}/fabric-network/crypto-config/peerOrganizations/techcombank.example.com/users/Admin@techcombank.example.com/msp" \
        "${SWARM_NODE_SSH_USER}@${NODE_IP}:${SWARM_NODE_PROJECT_ROOT_PATH}/fabric-network/crypto-config/peerOrganizations/techcombank.example.com/users/Admin@techcombank.example.com/" \
        || { echo "ERROR: Failed to copy Admin MSP to ${NODE_IP}. Skipping this node."; NODE_COUNTER=$((NODE_COUNTER+1)); continue; }

    scp "${COORDINATOR_PROJECT_ROOT_PATH}/fabric-network/crypto-config/peerOrganizations/techcombank.example.com/peers/peer0.techcombank.example.com/tls/ca.crt" \
        "${SWARM_NODE_SSH_USER}@${NODE_IP}:${SWARM_NODE_PROJECT_ROOT_PATH}/fabric-network/crypto-config/peerOrganizations/techcombank.example.com/peers/peer0.techcombank.example.com/tls/" \
        || { echo "ERROR: Failed to copy Peer TLS CA to ${NODE_IP}. Skipping this node."; NODE_COUNTER=$((NODE_COUNTER+1)); continue; }

    scp "${COORDINATOR_PROJECT_ROOT_PATH}/fabric-network/crypto-config/ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt" \
        "${SWARM_NODE_SSH_USER}@${NODE_IP}:${SWARM_NODE_PROJECT_ROOT_PATH}/fabric-network/crypto-config/ordererOrganizations/example.com/orderers/orderer.example.com/tls/" \
        || { echo "ERROR: Failed to copy Orderer TLS CA to ${NODE_IP}. Skipping this node."; NODE_COUNTER=$((NODE_COUNTER+1)); continue; }

    # --- 4. Configure docker-compose.yaml with Coordinator IP on Swarm Node ---
    echo "4. Updating docker-compose.yaml with Coordinator IP on ${NODE_IP}..."
    ssh "${SWARM_NODE_SSH_USER}@${NODE_IP}" "cd ${SWARM_NODE_PROJECT_ROOT_PATH} && \
        sed -i 's/COORDINATOR_DEVICE_IP/${COORDINATOR_DEVICE_IP}/g' docker-compose.yaml" \
        || { echo "ERROR: Failed to update docker-compose.yaml on ${NODE_IP}. Skipping this node."; NODE_COUNTER=$((NODE_COUNTER+1)); continue; }

    # --- 5. Bring up Swarm Node Application ---
    echo "5. Building and bringing up 'swarm_node_app' on ${NODE_IP}..."
    ssh "${SWARM_NODE_SSH_USER}@${NODE_IP}" "cd ${SWARM_NODE_PROJECT_ROOT_PATH} && \
        docker-compose build swarm_node_app && \
        NODE_ID=${NODE_ID} docker-compose up -d swarm_node_app" \
        || { echo "ERROR: Failed to bring up swarm_node_app on ${NODE_IP}. Skipping this node."; NODE_COUNTER=$((NODE_COUNTER+1)); continue; }

    echo "--- Swarm Node Runner: ${NODE_IP} (ID: ${NODE_ID}) Deployment Complete! ---"
    echo "Verify service: ssh ${SWARM_NODE_SSH_USER}@${NODE_IP} 'docker ps -f name=swarm_node_app_${NODE_ID}'"
    echo "Check logs: ssh ${SWARM_NODE_SSH_USER}@${NODE_IP} 'docker logs swarm_node_app_${NODE_ID}'"

    NODE_COUNTER=$((NODE_COUNTER+1))
done

echo ""
echo "--- All Swarm Node Runners Deployment Process Finished! ---"
echo "Review the output for any errors or skipped nodes."