#!/bin/bash
set -e

# --- CONFIGURATION ---
JAVA8_HOME="/usr/lib/jvm/java-8-openjdk-arm64/jre"
MAVEN_PROJECT_DIR="$HOME/WebGoat-Legacy"
CLIENT_PROJECT_DIR="$HOME/webgoat-client/webgoat-client"
SETTINGS_FILE="$HOME/.m2/settings.xml"
NEXUS_HOST="localhost"
NEXUS_MAVEN_REPO="webgoat-releases"
NEXUS_DOCKER_REPO="docker-hosted"
NEXUS_PORT_MAVEN=8081
NEXUS_PORT_DOCKER=8082
DOCKER_IMAGE_NAME="webgoat:6.0.1"
DOCKER_IMAGE_TAG="localhost:${NEXUS_PORT_DOCKER}/webgoat/webgoat:6.0.1"
WAR_NAME="WebGoat-6.0.1.war"
DEFAULT_PORT=8083
ALT_PORT=8084

wait_step() {
  echo "[INFO] Waiting 10 seconds..."
  sleep 10
}

log_info() {
  echo "--------------------------------------------------"
  echo "[INFO] $1"
  echo "--------------------------------------------------"
}

log_error() {
  echo "--------------------------------------------------"
  echo "[ERROR] $1"
  echo "--------------------------------------------------"
}

# --- HELPER FUNCTIONS ---
check_port_free() {
  ! lsof -i ":$1" >/dev/null 2>&1
}

stop_existing_containers() {
  log_info "Checking for existing WebGoat containers..."
  # Find containers using the same image
  existing_containers=$(docker ps -q --filter ancestor="$DOCKER_IMAGE_TAG")
  
  if [ -n "$existing_containers" ]; then
    log_info "Found existing containers: $existing_containers"
    log_info "Stopping existing containers..."
    docker stop $existing_containers
    wait_step
  else
    log_info "No existing containers found"
  fi
}

# --- ENV SETUP ---
log_info "Switching to Java 8..."
export JAVA_HOME="$JAVA8_HOME"
export PATH="$JAVA_HOME/bin:$PATH"
log_info "Using Java: $("$JAVA_HOME/bin/java" -version 2>&1 | head -n 1)"
wait_step

# --- PHASE 2: BUILD WEBGOAT ---
log_info "Building WebGoat with Maven..."
cd "$MAVEN_PROJECT_DIR"
mvn clean package -DskipTests
wait_step

log_info "Verifying build artifacts..."
ls -lh target/$WAR_NAME target/WebGoat-6.0.1-war-exec.jar
wait_step

# --- PHASE 3: DEPLOY TO NEXUS MAVEN REPO ---
log_info "Deploying artifacts to Nexus Maven repo..."
if [ -f "$SETTINGS_FILE" ]; then
  mvn deploy -DskipTests --settings "$SETTINGS_FILE"
else
  log_error "settings.xml not found at: $SETTINGS_FILE"
  exit 1
fi
wait_step

log_info "Deployed to Nexus: http://$NEXUS_HOST:$NEXUS_PORT_MAVEN/repository/$NEXUS_MAVEN_REPO/"
wait_step

# --- PHASE 4: VALIDATE MAVEN CONSUMER PROJECT ---
log_info "Clearing local Maven cache for WebGoat..."
rm -rf ~/.m2/repository/WebGoat/WebGoat/
wait_step

log_info "Building Maven consumer project (webgoat-client)..."
cd "$CLIENT_PROJECT_DIR"
mvn clean install
wait_step

# --- PHASE 5: BUILD & PUSH DOCKER IMAGE TO NEXUS ---
log_info "Building Docker image: $DOCKER_IMAGE_NAME"
cd "$MAVEN_PROJECT_DIR"
docker build -t "$DOCKER_IMAGE_NAME" .
wait_step

log_info "Tagging Docker image for Nexus..."
docker tag "$DOCKER_IMAGE_NAME" "$DOCKER_IMAGE_TAG"
wait_step

log_info "Pushing Docker image to Nexus Docker repo..."
docker login localhost:$NEXUS_PORT_DOCKER -u admin -p Onosedeba9201==
docker push "$DOCKER_IMAGE_TAG"
wait_step

# --- PHASE 5B: VALIDATE DOCKER PULL AND RUN ---
log_info "Removing local Docker image for pull validation..."
docker rmi -f "$DOCKER_IMAGE_TAG" || true
wait_step

log_info "Pulling image back from Nexus..."
docker pull "$DOCKER_IMAGE_TAG"
wait_step

# --- CONTAINER MANAGEMENT ---
stop_existing_containers

# --- PORT HANDLING ---
if check_port_free $DEFAULT_PORT; then
  PORT=$DEFAULT_PORT
elif check_port_free $ALT_PORT; then
  PORT=$ALT_PORT
  log_info "⚠️ Port $DEFAULT_PORT is busy. Switching to fallback port $ALT_PORT..."
else
  log_error "Both ports $DEFAULT_PORT and $ALT_PORT are busy."
  log_info "✅ Docker image pull validated successfully. Container not started."
  exit 0
fi

log_info "Running WebGoat container on port $PORT..."
if ! docker run -d --rm -p "$PORT:8080" --name "webgoat_$PORT" "$DOCKER_IMAGE_TAG"; then
  log_error "Failed to start container on port $PORT."
  exit 1
fi
wait_step

log_info "✅ Success: Access WebGoat at: http://localhost:$PORT/WebGoat"
log_info "Container ID: $(docker ps -q --filter ancestor="$DOCKER_IMAGE_TAG")"