# Define Base image, already have foundry available
FROM ghcr.io/foundry-rs/foundry


# Set the working directory in the container to /app again.
WORKDIR /app

COPY deployments/31337/state.txt /app/state.txt

# Define an environment variable for the port.
# Default to 8000 if not provided.
ARG PORT=8000
ENV PORT=${PORT}

# Define the command to run when the container starts.
# found the last dumped state in matching folder
# CMD ["/app/scripts/load-chain.sh"]
CMD ["anvil --host 0.0.0.0 --port ${PORT}"]
