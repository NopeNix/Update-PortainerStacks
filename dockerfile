FROM mcr.microsoft.com/powershell:alpine-3.20

# Install necessary packages
RUN apk update && \
apk add --no-cache supervisor 
RUN pwsh -c Install-Module Pode -Force

# Create a working directory & copy the necessary files
WORKDIR /data
COPY ./data /data/

# Make the entrypoint script executable
RUN chmod 700 /data/entrypoint.sh
RUN chmod +x /data/entrypoint.sh

# Make a folder for logging (optional but useful)
RUN mkdir -p /var/log

# Configure Supervisord
RUN mkdir -p /var/log/supervisor

# Set default command to run supervisord
CMD ["supervisord", "-n", "-c", "/data/supervisord.conf"]