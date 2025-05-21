FROM mcr.microsoft.com/powershell:alpine-3.20

# Install necessary packages
RUN apk update && \
apk add --no-cache supervisor docker-cli bash curl jq docker-cli-compose
RUN pwsh -c Install-Module Pode -Force


# Install regctl via edge testing repo
RUN sed -i 's/https:\/\/dl-cdn.alpinelinux.org\/alpine\/[^/]*\/main/https:\/\/dl-cdn.alpinelinux.org\/alpine\/edge\/main/g' /etc/apk/repositories
RUN sed -i 's/https:\/\/dl-cdn.alpinelinux.org\/alpine\/[^/]*\/community/https:\/\/dl-cdn.alpinelinux.org\/alpine\/edge\/community/g' /etc/apk/repositories
RUN echo 'https://dl-cdn.alpinelinux.org/alpine/edge/testing' | tee -a /etc/apk/repositories
RUN apk update && \
apk add --no-cache regclient

# Create a working directory & copy the necessary files
WORKDIR /data
COPY ./data /data/

# Make the entrypoint script executable
RUN chmod 700 /data/entrypoint.sh
RUN chmod +x /data/entrypoint.sh

# Make the dockcheck.sh script executable
RUN chmod 555 /data/dockcheck.sh
RUN chmod +x /data/dockcheck.sh

# Make a folder for logging (optional but useful)
RUN mkdir -p /var/log

# Configure Supervisord
RUN mkdir -p /var/log/supervisor

# Set default command to run supervisord
CMD ["supervisord", "-n", "-c", "/data/supervisord.conf"]