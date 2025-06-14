#!/bin/bash

# fabric-network/scripts/generate-certs.sh

echo "### Generating crypto material and genesis block ###" # Message for clarity when the script runs

# Clean up any previous crypto material and channel artifacts and create new ones
echo "Removing old crypto-config and channel-artifacts..."
rm -rf ../crypto-config
rm -rf ../channel-artifacts
mkdir -p ../channel-artifacts

# Temporarily set Path to tools (assuming fabric-samples binaries are in your PATH or current dir)
export PATH=$(pwd)/../bin:$PATH
export FABRIC_CFG_PATH=$(pwd)/../config # Point to a config folder if using custom configs (not in this basic example)

# Generate crypto material
echo "Generating crypto material with cryptogen..."
# Use the cryptogen tool to generate certificates and keys for organizations and peers
# Configuration is read from crypto-config.yaml
cryptogen generate --config=./crypto-config.yaml --output=../crypto-config
# Check if the previous code failed
if [ $? -ne 0 ]; then
  echo "Failed to generate crypto material."
  exit 1
fi

# Generate genesis block - the first block in our blockchain
echo "Generating orderer genesis block..."
configtxgen -profile TwoOrgsOrdererGenesis -channelID system-channel -outputBlock ../channel-artifacts/genesis.block #Generate genesis block by rules defined in configtx.yaml file
if [ $? -ne 0 ]; then
  echo "Failed to generate orderer genesis block."
  exit 1
fi

# Generate channel transaction
echo "Generating channel configuration transaction 'mychannel.tx'..."
configtxgen -profile TwoOrgsApplicationChannel -outputCreateChannelTx ../channel-artifacts/mychannel.tx -channelID mychannel
if [ $? -ne 0 ]; then
  echo "Failed to generate channel configuration transaction."
  exit 1
fi

# Generate anchor peer update for Techcombank
echo "Generating anchor peer update for Techcombank..."
configtxgen -profile TwoOrgsApplicationChannel -outputAnchorPeersUpdate ../channel-artifacts/TechcombankMSPanchors.tx -channelID mychannel -asOrg TechcombankMSP
if [ $? -ne 0 ]; then
  echo "Failed to generate anchor peer update for TechcombankMSP."
  exit 1
fi

echo "Crypto material and channel artifacts generated successfully."