#!/bin/bash

# --- CẤU HÌNH (Cập nhật các giá trị này) ---
AWS_REGION="ap-southeast-1"  # Ví dụ: Singapore, thay đổi nếu cần
S3_BUCKET_NAME="durian-bucket-titan"  # Use the provided bucket name

COORDINATOR_PROJECT_ROOT_PATH="/home/ubuntu/<YOUR_PROJECT_ROOT_DIRECTORY_NAME>"
SWARM_NODE_PROJECT_ROOT_PATH="/home/ubuntu/<YOUR_PROJECT_ROOT_DIRECTORY_NAME>"
SWARM_NODE_SSH_USER="ubuntu"
SSH_KEY_PATH="/home/ubuntu/.ssh/my-swarm-key.pem"

# Danh sách các IP RIÊNG TƯ (Private IPs) của các Swarm Node Runners
SWARM_NODE_IPS=(
    "PRIVATE_IP_OF_RISK_NODE"  # Ví dụ: 10.0.1.10
    "PRIVATE_IP_OF_CRM_NODE"   # Ví dụ: 10.0.1.11
)

# Danh sách NODE_ID tương ứng với các IP
NODE_IDS=(
    "risk"
    "crm"
)

# IP RIÊNG TƯ của Coordinator Device
COORDINATOR_DEVICE_IP="<COORD_PRIVATE_IP>"  # Ví dụ: 10.0.1.5

# --- HÀM HỖ TRỢ ---
run_on_remote() {
    local NODE_IP=$1
    local COMMAND=$2
    echo "--> Running on ${NODE_IP}: ${COMMAND}"
    ssh -i "${SSH_KEY_PATH}" "${SWARM_NODE_SSH_USER}@${NODE_IP}" "${COMMAND}"
}

copy_to_remote() {
    local NODE_IP=$1
    local LOCAL_PATH=$2
    local REMOTE_PATH=$3
    echo "--> Copying ${LOCAL_PATH} to ${NODE_IP}:${REMOTE_PATH}"
    scp -i "${SSH_KEY_PATH}" -r "${LOCAL_PATH}" "${SWARM_NODE_SSH_USER}@${NODE_IP}:${REMOTE_PATH}"
}

# --- TRIỂN KHAI CHO TỪNG SWARM NODE ---
if [ ${#SWARM_NODE_IPS[@]} -ne ${#NODE_IDS[@]} ]; then
    echo "ERROR: Number of SWARM_NODE_IPS does not match number of NODE_IDS."
    exit 1
fi

for i in "${!SWARM_NODE_IPS[@]}"; do
    NODE_IP=${SWARM_NODE_IPS[i]}
    NODE_ID=${NODE_IDS[i]}

    echo "--- Deploying Swarm Node '${NODE_ID}' at IP: ${NODE_IP} ---"

    # 1. Cập nhật mã nguồn và Dockerfile trên Swarm Node
    run_on_remote "${NODE_IP}" "cd ${SWARM_NODE_PROJECT_ROOT_PATH} && git pull origin main" || { echo "ERROR: Git pull failed for ${NODE_ID}. Exiting."; exit 1; }

    # 2. Xây dựng lại Docker Image
    run_on_remote "${NODE_IP}" "cd ${SWARM_NODE_PROJECT_ROOT_PATH} && docker build -f swarm_node/Dockerfile -t swarm_node_app ." || { echo "ERROR: Docker build failed for ${NODE_ID}. Exiting."; exit 1; }

    # 3. Dừng và xóa container cũ nếu có
    run_on_remote "${NODE_IP}" "docker stop ${NODE_ID} || true"
    run_on_remote "${NODE_IP}" "docker rm ${NODE_ID} || true"

    # 4. Chạy Swarm Node App container mới
    run_on_remote "${NODE_IP}" "docker run -d --restart always \
        --name ${NODE_ID} \
        -e NODE_ID=${NODE_ID} \
        -e COORDINATOR_ENDPOINT=http://${COORDINATOR_DEVICE_IP}:8001 \
        -e NODE_PORT=8000 \
        -e S3_BUCKET_NAME=${S3_BUCKET_NAME} \
        swarm_node_app" || { echo "ERROR: Docker run failed for ${NODE_ID}. Exiting."; exit 1; }

    # Optional: Sleep for a few seconds to ensure the container starts properly
    sleep 5

    # 5. Kiểm tra trạng thái container mới
    run_on_remote "${NODE_IP}" "docker ps -q -f name=${NODE_ID}" || { echo "ERROR: Docker container for ${NODE_ID} is not running. Exiting."; exit 1; }

    echo "--- Swarm Node '${NODE_ID}' deployed successfully ---"
done

echo "All Swarm Nodes deployment scripts initiated."
echo "Check logs on each node using 'docker logs <NODE_ID>' for troubleshooting."
