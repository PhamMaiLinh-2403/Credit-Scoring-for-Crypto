import requests
import time
import os
import json
import threading
import random
import hashlib # Make sure hashlib is imported for hashing

from flask import Flask, request, jsonify

from shared_libs.central_registry import CentralRegistry
from shared_libs.aggregator import Aggregator
from shared_libs.blockchain_sdk import BlockchainClientSDK 

app = Flask(__name__)

class Coordinator:
    def __init__(self, coordinator_id):
        self.coordinator_id = coordinator_id
        self.central_registry = CentralRegistry()
        self.aggregator = Aggregator()
        
        self.current_round = 0
        self.current_global_model = self._initialize_global_model()

        # Attributes for managing update collection per round
        self._received_updates_this_round = {}
        self._updates_expected_count = 0
        self._round_completion_event = threading.Event()
        self._update_lock = threading.Lock() # To protect _received_updates_this_round

        # Dictionary to store node endpoints for direct communication
        self.node_endpoints = {}

        # --- ADD THIS LINE: Initialize the BlockchainClientSDK ---
        self.blockchain_client = BlockchainClientSDK(client_id=coordinator_id) 
        # In a real setup, you might pass a config dictionary here for cert paths, etc.
        # Example: self.blockchain_client = BlockchainClientSDK(client_id=coordinator_id, config={'cert_path': 'path/to/cert.pem'})
        # --------------------------------------------------------

        print(f"Coordinator '{self.coordinator_id}' initialized.")

    def _initialize_global_model(self):
        # A simple initial global model for demonstration
        # In a real scenario, this might come from a pre-trained model or be all zeros
        # Need to know all possible features across all nodes to initialize.
        # For simplicity, let's assume some common features.
        model_path = '/app/models/latest_global_model.json'

        if os.path.exists(model_path):
            with open(model_path, 'r') as f:
                print('Coordinator: Loaded existing global model from disk')
                return json.load(f)
        else:
            print('Coordinator: No existing global model found. Creating a new one.')
            return None

    def register_node(self, node_id, endpoint_url):
        print(f"Coordinator: Received registration request for Node {node_id} at {endpoint_url}")
        success = self.central_registry.register_node(node_id, endpoint_url)
        if success:
            # Also add to our local dictionary if not already there, for direct communication
            with self._update_lock: # Protect access to node_endpoints
                if node_id not in self.node_endpoints:
                    self.node_endpoints[node_id] = endpoint_url
                    print(f"Coordinator: Added Node {node_id} to active endpoints.")
            return True
        return False
    
    def distribute_global_model(self):
        print("[STEP 1: Distributing Global Model]")
        registered_nodes = self.central_registry.get_registered_nodes()
        self._updates_expected_count = len(registered_nodes)
        self._received_updates_this_round = {} # Reset for new round
        self._round_completion_event.clear() # Clear the event for the new round

        if not registered_nodes:
            print("Coordinator: No nodes to distribute model to.")
            return

        for node_id, endpoint_url in registered_nodes.items():
            try:
                # Assuming nodes have an endpoint to receive the model
                target_url = f"{endpoint_url}/model_update" 
                headers = {'Content-Type': 'application/json'}
                payload = {
                    'round_num': self.current_round,
                    'global_model': self.current_global_model
                }
                requests.post(target_url, json=payload, headers=headers, timeout=5)
                print(f"Coordinator: Sent global model to node {node_id}")
            except requests.exceptions.RequestException as e:
                print(f"Coordinator: Error sending model to node {node_id} at {endpoint_url}: {e}")
                # Potentially unregister the node or mark as inactive

    def receive_model_update(self, node_id, round_num, local_model):
        with self._update_lock:
            if round_num != self.current_round:
                print(f"Coordinator: Received out-of-round update from {node_id} (Expected {self.current_round}, Got {round_num}). Ignoring.")
                return False

            if node_id in self._received_updates_this_round:
                print(f"Coordinator: Node {node_id} already submitted update for round {round_num}. Ignoring duplicate.")
                return False

            self._received_updates_this_round[node_id] = local_model
            print(f"Coordinator: Received update from Node {node_id} for round {round_num}.")

            if len(self._received_updates_this_round) >= self._updates_expected_count:
                print("Coordinator: All expected updates received for this round. Signaling completion.")
                self._round_completion_event.set() # Signal that all updates are in
            return True

    def wait_for_local_updates(self, timeout=60):
        print(f"\n[STEP 2: Waiting for Local Updates (Timeout: {timeout} seconds)]")
        # Wait for the event to be set, or for the timeout to expire
        completed = self._round_completion_event.wait(timeout)
        if not completed and len(self._received_updates_this_round) < self._updates_expected_count:
            print("Coordinator: Timeout waiting for all local model updates. Proceeding with received updates.")
        elif completed:
            print("Coordinator: All expected local model updates received.")

    def run_swarm_learning_round(self):
        self.current_round += 1
        print(f"\n--- Coordinator: Starting Swarm Learning Round {self.current_round} ---")

        registered_nodes = self.central_registry.get_registered_nodes()
        if not registered_nodes:
            print("Coordinator: No nodes registered. Skipping round.")
            return

        # Reset for the new round and distribute the global model
        self.distribute_global_model()
        
        # Wait for local updates from participating nodes
        self.wait_for_local_updates(timeout=60) # Wait up to 60 seconds for updates

        # --- STEP 3: Aggregation ---
        print("\n[STEP 3: Aggregating received models]")
        local_models_list = list(self._received_updates_this_round.values())
        if not local_models_list:
            print("Coordinator: No models to aggregate. Skipping aggregation.")
            return

        aggregated_model = self.aggregator.aggregate_models(local_models_list)
        self.current_global_model = aggregated_model
        print("Coordinator: Models aggregated successfully.")

        # --- STEP 4: Record Aggregation Hash (Now using the BlockchainClientSDK) ---
        aggregated_model_json = json.dumps(aggregated_model, sort_keys=True).encode('utf-8')
        aggregation_hash = hashlib.sha256(aggregated_model_json).hexdigest()
        
        print(f"\n[STEP 4: Recording Aggregation Hash]")
        # CALL THE BLOCKCHAIN SDK HERE
        try:
            self.blockchain_client.record_aggregation_hash(
                round_num=self.current_round, 
                model_hash=aggregation_hash,
                aggregated_by=self.coordinator_id 
            )
            print(f"Coordinator: Aggregation hash recorded on blockchain for round {self.current_round}.")
        except Exception as e:
            print(f"Coordinator: ERROR recording aggregation hash on blockchain: {e}")
        # ------------------------------------
        
        # --- Save the model after each round to a volume ---
        model_save_dir = "/app/models" # Mounted via Docker volume
        os.makedirs(model_save_dir, exist_ok=True)
        model_filename = f"global_model_round_{self.current_round}.json"
        model_filepath = os.path.join(model_save_dir, model_filename)
        
        try:
            with open(model_filepath, 'w') as f:
                json.dump(self.current_global_model, f)
            print(f"Coordinator: Global model for round {self.current_round} saved to {model_filepath}")
        except Exception as e:
            print(f"Coordinator: ERROR saving model for round {self.current_round}: {e}")

        print(f"--- Coordinator: Round {self.current_round} Complete ---")
        return self.current_global_model


# --- Flask Application Setup ---
# Initialize the Coordinator instance (globally accessible for Flask routes)
Coordinator.instance = None # Will be set in if __name__ == '__main__'

@app.route('/register', methods=['POST'])
def register():
    """Endpoint for nodes to register with the Coordinator."""
    data = request.get_json()
    node_id = data.get('node_id')
    endpoint_url = data.get('endpoint_url')
    
    if not node_id or not endpoint_url:
        return jsonify({"status": "failure", "message": "Missing node_id or endpoint_url"}), 400

    if Coordinator.instance.register_node(node_id, endpoint_url):
        return jsonify({"status": "success", "message": f"Node {node_id} registered."}), 200
    return jsonify({"status": "failure", "message": f"Node {node_id} already registered or failed."}), 400

@app.route('/submit_model_update', methods=['POST'])
def submit_model_update():
    """Endpoint for nodes to submit their local model updates."""
    data = request.get_json()
    node_id = data.get('node_id')
    round_num = data.get('round_num')
    local_model = data.get('local_model')

    if not node_id or round_num is None or not local_model:
        return jsonify({"status": "failure", "message": "Missing node_id, round_num, or local_model"}), 400

    if Coordinator.instance.receive_model_update(node_id, round_num, local_model):
        return jsonify({"status": "success", "message": f"Model update from {node_id} received for round {round_num}."}), 200
    return jsonify({"status": "failure", "message": f"Failed to process update from {node_id} for round {round_num}."}), 400

def start_training_rounds():
    """Function to continuously run swarm learning rounds."""
    MAX_ROUNDS = 5
    round_count = 0
    while round_count <MAX_ROUNDS:
        time.sleep(5) # Wait a bit before starting the next round
        if Coordinator.instance.central_registry.get_registered_nodes():
            Coordinator.instance.run_swarm_learning_round()
            round_count += 1
        else:
            print("Coordinator: No nodes registered. Waiting for registrations...")
            time.sleep(10) # Wait longer if no nodes are registered
    print(f'Coordinator: Training completed after {MAX_ROUNDS} rounds.')

if __name__ == '__main__':
    COORDINATOR_ID = os.environ.get('COORDINATOR_ID', 'coordinator-default')
    
    # Initialize the Coordinator instance and make it globally accessible for Flask routes
    Coordinator.instance = Coordinator(COORDINATOR_ID)

    # Start a separate thread for running the training rounds
    training_thread = threading.Thread(target=start_training_rounds)
    training_thread.daemon = True # Allow the main program to exit even if this thread is running
    training_thread.start()

    # Run the Flask application
    # This will be accessible on the host's port 5000 (default) inside a Docker container
    # For Docker, you usually bind to '0.0.0.0' to be accessible externally
    app.run(host='0.0.0.0', port=5000, debug=False) 