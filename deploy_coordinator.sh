#!/bin/bash

# --- Configuration ---
# IMPORTANT: Replace with the actual absolute path to your project's root directory
COORDINATOR_PROJECT_ROOT_PATH="/home/youruser/your-project" # Example: /home/ubuntu/my-blockchain-swarm

# --- Error Handling ---
set -e # Exit immediately if a command exits with a non-zero status

echo "--- Starting Coordinator Device Deployment ---"
echo "Project Root: ${COORDINATOR_PROJECT_ROOT_PATH}"

# --- 1. Initial Project Setup ---
echo "1. Navigating to project root and pulling latest code..."
cd "${COORDINATOR_PROJECT_ROOT_PATH}"
git pull origin main || { echo "ERROR: Failed to pull Git repository. Exiting."; exit 1; }

# Create the shared Docker network (local to this device)
echo "2. Creating Docker network 'swarm-network'..."
docker network create swarm-network || true # '|| true' prevents error if it already exists

# --- 2. Hyperledger Fabric Network Initialization ---
echo "3. Generating crypto material and channel artifacts..."
cd "${COORDINATOR_PROJECT_ROOT_PATH}/fabric-network"
./scripts/generate_certs.sh || { echo "ERROR: Failed to generate crypto material. Exiting."; exit 1; }
./scripts/generate_channel_artifacts.sh || { echo "ERROR: Failed to generate channel artifacts. Exiting."; exit 1; }
cd "${COORDINATOR_PROJECT_ROOT_PATH}" # Go back to project root

echo "4. Bringing up Hyperledger Fabric services..."
docker-compose -f "${COORDINATOR_PROJECT_ROOT_PATH}/fabric-network/docker-compose-fabric.yaml" up -d || { echo "ERROR: Failed to bring up Fabric services. Exiting."; exit 1; }
echo "Waiting for Fabric services to stabilize (15 seconds)..."
sleep 15

# --- 3. Fabric Channel and Chaincode Deployment ---
echo "5. Deploying Fabric Channel and Chaincode..."
# IMPORTANT: This script is assumed to handle channel creation, peer joining,
# anchor peer update, chaincode installation, approval, and commitment.
"${COORDINATOR_PROJECT_ROOT_PATH}/fabric-network/scripts/deploy_chaincode.sh" || { echo "ERROR: Failed to deploy chaincode. Exiting."; exit 1; }
echo "Waiting for chaincode to be fully ready (10 seconds)..."
sleep 10

# --- 4. Coordinator Application Deployment ---
echo "6. Building and bringing up the 'coordinator' application..."
docker-compose build coordinator || { echo "ERROR: Failed to build coordinator app. Exiting."; exit 1; }
docker-compose up -d coordinator || { echo "ERROR: Failed to bring up coordinator app. Exiting."; exit 1; }

# --- 5. Get Coordinator IP for Swarm Node Runners ---
# This dynamically finds the IP address of the Coordinator Device.
# Adjust 'eth0'/'wlan0' based on your primary network interface name.
COORDINATOR_DEVICE_IP=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
if [ -z "$COORDINATOR_DEVICE_IP" ]; then
    COORDINATOR_DEVICE_IP=$(ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
fi

if [ -z "$COORDINATOR_DEVICE_IP" ]; then
    echo "ERROR: Could not automatically determine Coordinator Device IP."
    echo "Please find it manually (e.g., 'ip a', 'ifconfig') and note it down."
    echo "You will need it for the swarm node deployment."
    # We don't exit here, as deployment might continue, but the user needs the IP.
else
    echo "--- Coordinator Device IP: ${COORDINATOR_DEVICE_IP} ---"
    echo "Please note this IP. You will use it when deploying Swarm Node Runners."
fi

echo "--- Coordinator Device Deployment Complete! ---"
echo "Verify services: 'docker ps'"
echo "Check logs: 'docker logs coordinator' and other Fabric containers."
echo "Ensure firewall rules are open for ports 7050, 7051, 7054, 5984, 8001."