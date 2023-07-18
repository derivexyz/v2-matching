# Define the first stage. This is where we're going to clone the repositories and set up the SSH keys.
# We're using Ubuntu as the base image for this stage.
FROM ubuntu:latest as builder

# Set the working directory in the container to /app. This is where our commands will run.
WORKDIR /app

# Update the list of available packages and install Git.
RUN apt-get update
RUN apt-get -y install git

# Set up the SSH keys for git clone.
# Create the .ssh directory and set the correct permissions.
RUN mkdir /root/.ssh/
ARG SSH_PRIVATE_KEY
# Save the SSH private key environment variable to a file and set the correct permissions and ownership.
# Then, add a configuration for github.com to the SSH config file.
RUN echo "${SSH_PRIVATE_KEY}" > /root/.ssh/id_rsa && \
    chmod 600 /root/.ssh/id_rsa && \
    chown -R root:root /root/.ssh && \
    echo "Host github.com\n\tHostName github.com\n\tUser git\n\tIdentityFile /root/.ssh/id_rsa\n\tStrictHostKeyChecking no\n" >> /root/.ssh/config

# Clone the necessary repositories.
RUN git clone git@github.com:lyra-finance/v2-core.git -b chore/deployment-fixes core
RUN git clone git@github.com:lyra-finance/v2-matching.git -b feat/deployment matching

# Define the second stage. This is where we're going to use the Foundry image and set up the environment for running the script.
FROM ghcr.io/foundry-rs/foundry

# Set the working directory in the container to /app again.
WORKDIR /app

# Copy the cloned repositories and the SSH keys from the first stage into the current stage.
COPY --from=builder /app/core ./core
COPY --from=builder /app/matching ./matching
COPY --from=builder /root/.ssh /root/.ssh

# Copy the startup script from the host machine into the image.
COPY ./scripts/start-local.sh /app/start-local.sh


# Define an environment variable for the private key.
ARG PRIVATE_KEY

# Define the command to run when the container starts.
# We're using /bin/bash to ensure that the script is run in a Bash shell.
CMD ["/app/start-local.sh"]
# CMD ["/bin/bash", "/app/start-local.sh"]
# CMD ["/bin/bash", "/app/start-local.sh"]

