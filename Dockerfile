# Define Base image, already have foundry available
FROM ghcr.io/foundry-rs/foundry

# Set the working directory in the container to /app again.
WORKDIR /app

# Copy the entire context to the container
COPY . .

# Make the start-local.sh script executable
RUN chmod +x /app/scripts/start-local.sh

# Define an environment variable for the private key.
ARG PRIVATE_KEY
ENV PRIVATE_KEY=${PRIVATE_KEY}

# Define an environment variable for the port.
# Default to 8000 if not provided.
ARG PORT=8000
ENV PORT=${PORT}

# Define the command to run when the container starts.
CMD ["/app/scripts/start-local.sh"]
