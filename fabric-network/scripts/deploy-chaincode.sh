#!/bin/bash

# fabric-network/scripts/deploy-chaincode.sh

echo "### Deploying HashRecorderChaincode ###"

export PATH=$(pwd)/../bin:$PATH # Assuming Fabric binaries are accessible
export FABRIC_CFG_PATH=$(pwd)/../config

CHANNEL_NAME="mychannel"
CHAINCODE_NAME="hash_recorder_chaincode"
CHAINCODE_PATH="../../chaincode" # Path relative to this script for the Go chaincode
CHAINCODE_LANG="golang"
CHAINCODE_VERSION="1.0"
CORE_PEER_TLS_ENABLED=true
ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

# Set environment variables for Techcombank's peer
set_peer0_techcombank_env() {
  export CORE_PEER_LOCALMSPID="TechcombankMSP"
  export CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/techcombank.example.com/tls/tlscacerts/tlsca.techcombank.example.com-cert.pem
  export CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/techcombank.example.com/users/Admin@techcombank.example.com/msp
  export CORE_PEER_ADDRESS=peer0.techcombank.example.com:7051
}

# --- Step 1: Package Chaincode ---
echo "Packaging chaincode '$CHAINCODE_NAME' v$CHAINCODE_VERSION..."
set_peer0_techcombank_env # Ensure env is set for packaging
peer lifecycle chaincode package ${CHAINCODE_NAME}.tar.gz \
  --path ${CHAINCODE_PATH} \
  --lang ${CHAINCODE_LANG} \
  --label ${CHAINCODE_NAME}_${CHAINCODE_VERSION}
if [ $? -ne 0 ]; then
  echo "Failed to package chaincode."
  exit 1
fi
echo "Chaincode packaged successfully."

# --- Step 2: Install Chaincode on Peer ---
echo "Installing chaincode '$CHAINCODE_NAME' on peer0.techcombank.example.com..."
set_peer0_techcombank_env
peer lifecycle chaincode install ${CHAINCODE_NAME}.tar.gz
if [ $? -ne 0 ]; then
  echo "Failed to install chaincode."
  exit 1
fi

# Get the package ID
PACKAGE_ID=$(peer lifecycle chaincode queryinstalled --output json | jq -r ".installed_chaincodes[] | select(.label == \"${CHAINCODE_NAME}_${CHAINCODE_VERSION}\") | .package_id")
if [ -z "$PACKAGE_ID" ]; then
  echo "Failed to get chaincode package ID."
  exit 1
fi
echo "Chaincode installed with Package ID: $PACKAGE_ID"

# --- Step 3: Approve Chaincode Definition for Techcombank ---
echo "Approving chaincode definition for Techcombank on channel '$CHANNEL_NAME'..."
set_peer0_techcombank_env
peer lifecycle chaincode approveformyorg \
  -o orderer.example.com:7050 \
  --ordererTLSHostnameOverride orderer.example.com \
  --channelID $CHANNEL_NAME \
  --name $CHAINCODE_NAME \
  --version $CHAINCODE_VERSION \
  --package-id $PACKAGE_ID \
  --sequence 1 \
  --tls $CORE_PEER_TLS_ENABLED \
  --cafile $ORDERER_CA
if [ $? -ne 0 ]; then
  echo "Failed to approve chaincode for my org."
  exit 1
fi
echo "Chaincode definition approved for Techcombank."

# --- Step 4: Check Commit Readiness ---
echo "Checking chaincode commit readiness for '$CHAINCODE_NAME'..."
set_peer0_techcombank_env
peer lifecycle chaincode checkcommitreadiness \
  --channelID $CHANNEL_NAME \
  --name $CHAINCODE_NAME \
  --version $CHAINCODE_VERSION \
  --sequence 1 \
  --tls $CORE_PEER_TLS_ENABLED \
  --cafile $ORDERER_CA \
  --output json
# Check if Techcombank is true
READINESS=$(peer lifecycle chaincode checkcommitreadiness --channelID $CHANNEL_NAME --name $CHAINCODE_NAME --version $CHAINCODE_VERSION --sequence 1 --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA --output json | jq -r ".approvals.TechcombankMSP")
if [ "$READINESS" != "true" ]; then
  echo "Chaincode definition is not ready for commit by Techcombank. Check approvals."
  exit 1
fi
echo "Chaincode definition is ready for commit."

# --- Step 5: Commit Chaincode Definition ---
echo "Committing chaincode definition to channel '$CHANNEL_NAME'..."
set_peer0_techcombank_env # Ensure env is set for committing
peer lifecycle chaincode commitformyorg \
  -o orderer.example.com:7050 \
  --ordererTLSHostnameOverride orderer.example.com \
  --channelID $CHANNEL_NAME \
  --name $CHAINCODE_NAME \
  --version $CHAINCODE_VERSION \
  --sequence 1 \
  --tls $CORE_PEER_TLS_ENABLED \
  --cafile $ORDERER_CA \
  --peerAddresses peer0.techcombank.example.com:7051 \
  --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/techcombank.example.com/peers/peer0.techcombank.example.com/tls/tlscacerts/tlsca.techcombank.example.com-cert.pem
if [ $? -ne 0 ]; then
  echo "Failed to commit chaincode definition."
  exit 1
fi
echo "Chaincode definition committed successfully."

# --- Step 6: Initialize Chaincode (Invoke Init Function) ---
echo "Invoking chaincode '$CHAINCODE_NAME' Init function..."
set_peer0_techcombank_env
peer chaincode invoke -o orderer.example.com:7050 \
  --ordererTLSHostnameOverride orderer.example.com \
  --channelID $CHANNEL_NAME \
  --name $CHAINCODE_NAME \
  --peerAddresses peer0.techcombank.example.com:7051 \
  --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/techcombank.example.com/peers/peer0.techcombank.example.com/tls/tlscacerts/tlsca.techcombank.example.com-cert.pem \
  --tls $CORE_PEER_TLS_ENABLED \
  -c '{"function":"InitLedger","Args":[]}'
if [ $? -ne 0 ]; then
  echo "Failed to invoke Init function."
  exit 1
fi
echo "Chaincode Init function invoked successfully."

echo "Chaincode deployment complete."