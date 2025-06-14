#!/bin/bash

# fabric-network/scripts/create-channel.sh

echo "### Creating channel and joining peer ###"

export PATH=$(pwd)/../bin:$PATH # Assuming Fabric binaries are accessible
export FABRIC_CFG_PATH=$(pwd)/../config # Point to a config folder if using custom configs (not in this basic example)

CHANNEL_NAME="mychannel"
CORE_PEER_TLS_ENABLED=true
CORE_PEER_LOCALMSPID="TechcombankMSP"
CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/techcombank.example.com/tls/tlscacerts/tlsca.techcombank.example.com-cert.pem 
CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/techcombank.example.com/users/Admin@techcombank.example.com/msp
CORE_PEER_ADDRESS=peer0.techcombank.example.com:7051
ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

# Wait for orderer to be up
echo "Waiting for orderer to start..."
sleep 10 # Give orderer some time to initialize

# Create the channel
echo "Creating channel '$CHANNEL_NAME'..."
peer channel create -o orderer.example.com:7050 \
  -c $CHANNEL_NAME \
  --ordererTLSHostnameOverride orderer.example.com \
  -f ../channel-artifacts/mychannel.tx \
  --outputBlock ../channel-artifacts/${CHANNEL_NAME}.block \
  --tls $CORE_PEER_TLS_ENABLED \
  --cafile $ORDERER_CA
if [ $? -ne 0 ]; then
  echo "Failed to create channel."
  exit 1
fi

# Join peer0.techcombank.example.com to the channel
echo "Joining peer0.techcombank.example.com to channel '$CHANNEL_NAME'..."
peer channel join -b ../channel-artifacts/${CHANNEL_NAME}.block \
  --tls $CORE_PEER_TLS_ENABLED \
  --cafile $ORDERER_CA
if [ $? -ne 0 ]; then
  echo "Failed to join peer to channel."
  exit 1
fi

echo "Channel created and peer joined successfully."

# Update anchor peers for Techcombank (important for cross-org gossip)
echo "Updating anchor peers for Techcombank..."
peer channel update -o orderer.example.com:7050 \
  -c $CHANNEL_NAME \
  -f ../channel-artifacts/TechcombankMSPanchors.tx \
  --ordererTLSHostnameOverride orderer.example.com \
  --tls $CORE_PEER_TLS_ENABLED \
  --cafile $ORDERER_CA
if [ $? -ne 0 ]; then
  echo "Failed to update anchor peers."
  exit 1
fi
echo "Anchor peers updated for Techcombank."