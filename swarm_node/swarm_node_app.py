import requests
import time
import os
import random
import threading
import json
import pandas as pd
import numpy as np
from sklearn.linear_model import SGDRegressor

from flask import Flask, request, jsonify
import boto3
from io import BytesIO

app = Flask(__name__)

class SwarmNode:
    instance = None
    
    def __init__(self, node_id, coordinator_endpoint):
        self.node_id = node_id
        self.coordinator_endpoint = coordinator_endpoint  # e.g., "http://swarm-coordinator:5000"
        self.current_round = 0
        self._load_local_data()
        self.feature_set = self.X.columns.tolist()
        self.model_params = self._initialize_model()
        
        # Event to signal when a new global model is received and processed
        self._new_model_event = threading.Event()
        # Lock for protecting model_params and current_round during updates
        self._model_lock = threading.Lock()

        print(f"Swarm Node '{self.node_id}' initialized.")
        print(f"Node '{self.node_id}' initial model: {self.model_params}")
        print(f"Node '{self.node_id}' local data samples: {len(self.local_data)}")

    def _initialize_model(self):
        # Initializing a simple linear model with random coefficients and intercept
        return {
            'coef': {f: 0 for f in self.feature_set},
            'intercept': 0
        }
    
    def _load_local_data(self):
        # NODE_ID will be 'risk' or 'crm'
        if self.node_id == 'risk':
            file_name = "combined_risk.parquet"
        elif self.node_id == 'crm':
            file_name = "combined_crm.parquet"
        else:
            raise ValueError(f"Invalid NODE_ID: {self.node_id}. Must be 'risk' or 'crm'.")

        s3_key = f"nodes/{file_name}"  # Path within the bucket
        s3_bucket_name = os.environ.get('S3_BUCKET_NAME', 'durian-bucket-titan')  # Use the provided bucket name

        print(f"Node {self.node_id}: Loading data from S3://{s3_bucket_name}/{s3_key}...")

        try:
            s3 = boto3.client('s3')
            obj = s3.get_object(Bucket=s3_bucket_name, Key=s3_key)
            with BytesIO(obj['Body'].read()) as data_buffer:
                df = pd.read_parquet(data_buffer)

            if 'Target' not in df.columns:
                raise KeyError(f"Target column not found in data from S3://{s3_bucket_name}/{s3_key}")

            self.local_data = df
            self.X = df.drop(columns=['Target'])
            self.y = df['Target']
            self.feature_set = self.X.columns.tolist()
            print(f"Node {self.node_id}: Successfully loaded {len(df)} samples from S3.")

        except Exception as e:
            print(f"Node {self.node_id}: ERROR loading data from S3: {e}")
            raise

    def _train_local_model(self):
        print(f"Node {self.node_id}: Starting local training...")
        
        model = SGDRegressor(
            loss='squared_error',
            penalty=None, alpha=0.0001,
            max_iter=1, tol=None,
            learning_rate='constant', eta0=0.01,
            random_state=42  # for reproducibility
        )
        
        model.partial_fit(self.X[:1], self.y[:1])

        # Prepare initial parameters for SGDRegressor from our dict format
        initial_coef = np.array([self.model_params['coef'][f] for f in self.feature_set])
        initial_intercept = np.array([self.model_params['intercept']])

        model.coef_ = initial_coef
        model.intercept_ = initial_intercept

        model.partial_fit(self.X, self.y)
        
        # Update node's internal model parameters from the trained SGDRegressor
        for i, feature in enumerate(self.feature_set):
            self.model_params['coef'][feature] = model.coef_[i]
        self.model_params['intercept'] = model.intercept_[0]

        print(f"Node {self.node_id}: Completed local training. New params (subset): {self.get_current_params_subset()}")
        return self.model_params


    def _submit_local_update(self):
        """Submits the locally trained model parameters to the Coordinator."""
        retries = 3
        while retries > 0:
            try:
                print(f"Node {self.node_id}: Sending local model update for round {self.current_round} to Coordinator...")
                response = requests.post(
                    f"{self.coordinator_endpoint}/receive_model_update",  # NEW TARGET: Coordinator's endpoint
                    json={
                        "node_id": self.node_id,
                        "local_model_params": self.model_params,  # Send your locally trained model
                        "round_num": self.current_round
                    }
                )
                response.raise_for_status()  # Raise an exception for HTTP errors (4xx or 5xx)
                print(f"Node {self.node_id}: Update acknowledged by Coordinator: {response.json()}")
                return
            except requests.exceptions.RequestException as e:
                print(f"Node {self.node_id}: ERROR submitting update to Coordinator: {e}")
                retries -= 1
                if retries == 0:
                    print(f"Node {self.node_id}: Failed to submit model update after 3 retries.")
                    return
                time.sleep(5)  # Wait before retrying

    def _register_with_coordinator(self):
        """Registers this node with the central Coordinator."""
        try:
            print(f"Node {self.node_id}: Registering with Coordinator at {self.coordinator_endpoint}...")
            response = requests.post(
                f"{self.coordinator_endpoint}/register_node",
                json={"node_id": self.node_id, "endpoint_url": f"http://{os.environ.get('HOSTNAME', 'localhost')}:{os.environ.get('NODE_PORT', '5000')}"}
            )
            response.raise_for_status()
            print(f"Node {self.node_id}: Registration successful: {response.json()}")
            return True
        except requests.exceptions.RequestException as e:
            print(f"Node {self.node_id}: ERROR registering with Coordinator: {e}")
            # Exit or retry if registration fails (critical for node operation)
            time.sleep(5)
            self._register_with_coordinator()  # Simple retry


    # --- Flask API Endpoints ---
@app.route('/model_update', methods=['POST'])
def model_update_endpoint():
    node = SwarmNode.instance
    if not node:
        return jsonify({"status": "error", "message": "Node not initialized"}), 500

    data = request.get_json()
    global_model = data.get('global_model')
    round_num = data.get('round_num')

    if round_num is None:
        return jsonify({"status": "error", "message": "Missing 'round_num'"}), 400

    if global_model is None:
        print(f"Node {node.node_id}: No global model received, initializing new model.")
        global_model = node._initialize_model()
    elif not isinstance(global_model, dict) or 'coef' not in global_model or 'intercept' not in global_model:
        return jsonify({"status": "error", "message": "Invalid 'global_model' format"}), 400

    with node._model_lock:
        node.model_params = global_model
        node.current_round = round_num

    node._new_model_event.set()
    return jsonify({"status": "success"}), 200

def run_node_lifecycle(node_instance):
    """
    Manages the lifecycle of the Swarm Node:
    1. Registers with the Coordinator.
    2. Enters a loop:
       a. Waits for a new global model from the Coordinator.
       b. Performs local training.
       c. Submits local updates.
    """
    if not node_instance._register_with_coordinator():
        print(f"Node {node_instance.node_id}: Registration failed. Cannot start training lifecycle.")
        return

    while True:
        print(f"Node {node_instance.node_id}: Waiting for Coordinator to send global model for next round...")
        node_instance._new_model_event.clear()  # Clear the event before waiting for the next round
        
        if not node_instance._new_model_event.wait(timeout=120):  # Wait up to 120 seconds
            print(f"Node {node_instance.node_id}: Timeout waiting for global model. Re-registering...")
            if not node_instance._register_with_coordinator():
                print(f"Node {node_instance.node_id}: Failed to re-register. Exiting.")
                break
            continue  # Continue to wait for model in the next iteration

        with node_instance._model_lock:
            if node_instance.model_params is None:
                print(f"Node {node_instance.node_id}: No global model received — initializing local model.")
                node_instance.model_params = node_instance._initialize_model()
            else:
                print(f"Node {node_instance.node_id}: Received global model — proceeding with training.")

        print(f"Node {node_instance.node_id}: Proceeding with training for round {node_instance.current_round}.")
        
        node_instance._train_local_model()
        node_instance._submit_local_update()
        time.sleep(5)

if __name__ == '__main__':
    NODE_ID = os.environ.get('NODE_ID', f'swarm-node-{random.randint(1000, 9999)}')
    COORDINATOR_ENDPOINT = os.environ.get('COORDINATOR_ENDPOINT', 'http://localhost:5000')
    NODE_PORT = int(os.environ.get('NODE_PORT', 5001))  # Default to 5001 to avoid conflict with Coordinator

    # Initialize the SwarmNode instance and make it globally accessible for Flask routes
    SwarmNode.instance = SwarmNode(NODE_ID, COORDINATOR_ENDPOINT)

    # Start a separate thread for the node's training and submission lifecycle
    node_lifecycle_thread = threading.Thread(target=run_node_lifecycle, args=(SwarmNode.instance,))
    node_lifecycle_thread.daemon = True  # Allow the main program to exit even if this thread is running
    node_lifecycle_thread.start()

    # Run the Flask application
    app.run(host='0.0.0.0', port=NODE_PORT, debug=False)
