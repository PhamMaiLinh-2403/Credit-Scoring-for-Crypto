package main

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// ModelHashRecord defines the structure for storing model aggregation hashes on the ledger.
type ModelHashRecord struct {
	RoundNum    int    `json:"roundNum"`
	ModelHash   string `json:"modelHash"`
	AggregatedBy string `json:"aggregatedBy"` // e.g., "Coordinator-1"
	Timestamp   int64  `json:"timestamp"`    // Unix timestamp
}

// SmartContract defines the smart contract methods for recording and querying hashes.
type SmartContract struct {
	contractapi.Contract
}

// InitLedger is called when the smart contract is instantiated or upgraded.
// In this simple case, it doesn't need to do anything specific.
func (s *SmartContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	fmt.Printf("Chaincode: 'HashRecorderContract' initialized on ledger.\n")
	return nil
}

// RecordHash records a new model aggregation hash for a specific round.
// The key for the state will be "HASH_<RoundNum>".
func (s *SmartContract) RecordHash(ctx contractapi.TransactionContextInterface, roundNum int, modelHash string, aggregatedBy string) error {
	if roundNum <= 0 {
		return fmt.Errorf("Round number must be a positive integer")
	}
	if modelHash == "" {
		return fmt.Errorf("Model hash cannot be empty")
	}
	if aggregatedBy == "" {
		return fmt.Errorf("Aggregator ID cannot be empty")
	}

	// Create a unique key for this record
	hashKey := fmt.Sprintf("HASH_%d", roundNum)

	// Check if a hash for this round already exists to prevent overwrites (optional)
	existingRecordJSON, err := ctx.GetStub().GetState(hashKey)
	if err != nil {
		return fmt.Errorf("Failed to read from world state: %v", err)
	}
	if existingRecordJSON != nil {
		return fmt.Errorf("Hash for round %d already exists on the ledger. Cannot overwrite.", roundNum)
	}

	// Create the record object
	record := ModelHashRecord{
		RoundNum:    roundNum,
		ModelHash:   modelHash,
		AggregatedBy: aggregatedBy,
		Timestamp:   time.Now().Unix(), // Current Unix timestamp
	}

	// Marshal the record object to JSON
	recordJSON, err := json.Marshal(record)
	if err != nil {
		return fmt.Errorf("Failed to marshal record to JSON: %v", err)
	}

	// Put the record into the world state
	err = ctx.GetStub().PutState(hashKey, recordJSON)
	if err != nil {
		return fmt.Errorf("Failed to put record to world state: %v", err)
	}

	fmt.Printf("Chaincode: Recorded hash for Round %d (Hash: %s) by %s\n", roundNum, modelHash, aggregatedBy)
	return nil
}

// QueryHash retrieves a model aggregation hash record by its round number.
func (s *SmartContract) QueryHash(ctx contractapi.TransactionContextInterface, roundNum int) (*ModelHashRecord, error) {
	if roundNum <= 0 {
		return nil, fmt.Errorf("Round number must be a positive integer")
	}

	hashKey := fmt.Sprintf("HASH_%d", roundNum)
	recordJSON, err := ctx.GetStub().GetState(hashKey)
	if err != nil {
		return nil, fmt.Errorf("Failed to read from world state: %v", err)
	}
	if recordJSON == nil {
		return nil, fmt.Errorf("Hash record for round %d does not exist", roundNum)
	}

	var record ModelHashRecord
	err = json.Unmarshal(recordJSON, &record)
	if err != nil {
		return nil, fmt.Errorf("Failed to unmarshal JSON to ModelHashRecord: %v", err)
	}

	fmt.Printf("Chaincode: Queried hash for Round %d: %s\n", roundNum, record.ModelHash)
	return &record, nil
}

func main() {
	chaincode, err := contractapi.NewChaincode(&SmartContract{})
	if err != nil {
		fmt.Printf("Error creating hash recorder chaincode: %v\n", err)
		return
	}

	if err := chaincode.Start(); err != nil {
		fmt.Printf("Error starting hash recorder chaincode: %v\n", err)
	}
}