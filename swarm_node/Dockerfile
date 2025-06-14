# swarm_node/Dockerfile
FROM python:3.9-slim-buster 
# Or python:3.11-slim-bullseye as used in coordinator's example

WORKDIR /app

# Copy shared libraries first
# This ensures shared_libs is available for import by swarm_node_app.py
COPY shared_libs/ /app/shared_libs/

# Copy swarm_node application code
COPY swarm_node_app.py /app/swarm_node_app.py
# Copy this service's requirements
COPY requirements.txt /app/requirements.txt 

# Install dependencies
RUN pip install --no-cache-dir -r /app/requirements.txt

# Set PYTHONPATH to include the shared_libs directory
ENV PYTHONPATH=/app:$PYTHONPATH

# Command to run the swarm node application
CMD ["python", "swarm_node_app.py"]