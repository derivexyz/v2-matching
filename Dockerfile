# Define Base image, already have foundry available
FROM ghcr.io/foundry-rs/foundry

# Set the working directory in the container to /app again.
WORKDIR /app

COPY lib/ /app/lib/
COPY scripts/start-local.sh /app/scripts/start-local.sh
RUN chmod +x /app/scripts/start-local.sh

# Define an environment variable for the private key.
ARG PRIVATE_KEY
ENV PRIVATE_KEY=${PRIVATE_KEY}

# Define the command to run when the container starts.
# We're using /bin/bash to ensure that the script is run in a Bash shell.
CMD ["/app/scripts/start-local.sh"]

