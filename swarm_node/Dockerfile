# swarm_node/Dockerfile
# This Dockerfile is for the 'swarm_node' service.
# IMPORTANT: This assumes your docker-compose.yaml 'build.context' for 'swarm_node_app'
# is set to the PROJECT ROOT (e.g., context: . ) NOT './swarm_node'

FROM python:3.9-slim-buster

# Set the working directory inside the container
WORKDIR /app

# Copy shared libraries (from project root to /app/shared_libs)
COPY shared_libs/ /app/shared_libs/

# Copy the specific swarm_node application files from their relative paths to the root context
COPY swarm_node/swarm_node_app.py /app/swarm_node_app.py
COPY swarm_node/requirements.txt /app/requirements.txt
COPY swarm_node/data/ /app/data/ 
# Assuming data/ is inside swarm_node/

# Install dependencies (requirements.txt is now in /app/)
RUN pip install --no-cache-dir -r /app/requirements.txt

# Set PYTHONPATH to include the shared_libs directory for imports
# This ensures Python can find modules within /app/shared_libs
ENV PYTHONPATH=/app/shared_libs/:$PYTHONPATH

# Command to run the swarm node application
CMD ["python", "swarm_node_app.py"]