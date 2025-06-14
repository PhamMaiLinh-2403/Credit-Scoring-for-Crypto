# Hyperledger Fabric Network Setup for Swarm Learning

This directory contains the configuration files and scripts to set up a basic Hyperledger Fabric network. This network will host the `hash_recorder_chaincode` for recording aggregated model hashes.

## Prerequisites

1.  **Docker and Docker Compose:** Ensure you have Docker and Docker Compose installed (version 1.25.0+ for Compose, or Docker Desktop with Compose V2).
2.  **Fabric Binaries (Optional but Recommended):** For running the scripts, having `cryptogen`, `configtxgen`, `peer`, `osnadmin`, `fabric-ca-client` in your system's PATH is highly recommended. You can download them from the official Fabric documentation or typically find them within the `fabric-samples` repository's `bin` folder. For this setup, the scripts assume they are in `../bin` relative to the `fabric-network` directory.

## Setup Steps

Follow these steps in order to bring up the Fabric network and deploy the chaincode:

1.  **Navigate to the `fabric-network` directory:**
    ```bash
    cd your-project-root/fabric-network
    ```

2.  **Generate Crypto Material and Channel Artifacts:**
    This step creates the necessary certificates, private keys, and initial network configuration blocks.
    ```bash
    ./scripts/generate-certs.sh
    ```
    This will create `crypto-config/` and `channel-artifacts/` directories in the parent folder.

3.  **Start Fabric Network Components:**
    This will bring up the CA, Orderer, CouchDB, and Peer Docker containers.
    ```bash
    docker-compose -f docker-compose-fabric.yaml up -d
    ```
    Wait a few seconds for all containers to fully start. You can check their status with `docker ps`.

4.  **Create Channel and Join Peer:**
    This script creates the `mychannel` channel and joins `peer0.org1.example.com` to it.
    ```bash
    ./scripts/create-channel.sh
    ```

5.  **Deploy Chaincode:**
    This script packages, installs, approves, and commits your `hash_recorder_chaincode.go` onto `mychannel`.
    ```bash
    ./scripts/deploy-chaincode.sh
    ```

6.  **Verify Chaincode (Optional):**
    You can try to query the chaincode using the `peer` CLI to ensure it's deployed and working.
    First, ensure your environment variables are set correctly (you can source the `set_peer0_org1_env` function from `deploy-chaincode.sh` if needed, or manually set them as described in Fabric docs). Then try:
    ```bash
    # Example (ensure peer CLI is working and env variables are set as in deploy-chaincode.sh)
    # This will simulate querying a hash that doesn't exist yet
    peer chaincode query -o orderer.example.com:7050 --ordererTLSHostnameOverride orderer.example.com -C mychannel -n hash_recorder_chaincode --tls --cafile /opt/gopath/src/[github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem](https://github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem) -c '{"function":"QueryHash","Args":["1"]}'
    ```

## Teardown

To stop and remove the Fabric network:

1.  **Stop and remove containers:**
    ```bash
    docker-compose -f docker-compose-fabric.yaml down --volumes --remove-orphans
    ```
2.  **Clean up generated artifacts:**
    ```bash
    rm -rf ../crypto-config ../channel-artifacts
    ```

This will give you a fully functional Hyperledger Fabric network capable of recording your model hashes!