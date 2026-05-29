FROM node:20-slim

WORKDIR /app

# System deps for native modules (sqlite3) and curl healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Copy sources first so the postinstall build step has them
COPY package*.json ./
COPY tsconfig.json ./
COPY src ./src

# Installs deps and runs the build via the postinstall hook
RUN npm install

# Persisted SQLite data dir (used when USE_SQLITE=true)
RUN mkdir -p /app/data

EXPOSE 3000

CMD ["npm", "start"]
