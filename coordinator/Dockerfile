# coordinator/Dockerfile
FROM python:3.9-slim-buster

WORKDIR /app

# Copy shared libraries first
COPY shared_libs/ /app/shared_libs/

# Copy coordinator application code
COPY coordinator/coordinator.py /app/coordinator.py
COPY coordinator/requirements.txt /app/requirements.txt

# Install dependencies
RUN pip install --no-cache-dir -r /app/requirements.txt

# Set PYTHONPATH to include the shared_libs directory
ENV PYTHONPATH=/app:$PYTHONPATH

# Command to run the coordinator
CMD ["python", "coordinator.py"]