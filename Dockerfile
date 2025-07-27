FROM ubuntu:22.04

# Install build tools and nginx
RUN apt-get update && apt-get install -y \
    nasm \
    gcc \
    make \
    nginx \
    fcgiwrap \
    curl \
    procps \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /app/cgi-bin /app/src /app/test

# Copy source files
COPY src/* /app/src/
COPY Makefile /app/
COPY nginx.conf /etc/nginx/nginx.conf
COPY test_api.sh /app/

# Build the assembly programs
WORKDIR /app
RUN make all

# Set permissions
RUN chmod +x /app/cgi-bin/* /app/test_api.sh

# Expose nginx port
EXPOSE 80

# Start script
COPY start.sh /app/
RUN chmod +x /app/start.sh

CMD ["/app/start.sh"]