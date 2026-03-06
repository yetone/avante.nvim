#!/usr/bin/env bash
# Build script for optimized RAG service Docker image

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="${IMAGE_NAME:-avante-rag-service}"
IMAGE_TAG="${IMAGE_TAG:-gpu-optimized}"
REGISTRY="${REGISTRY:-}"  # Optional: your-registry.com/

# Print colored message
print_message() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    print_message "$RED" "Error: Docker is not installed"
    exit 1
fi

print_message "$GREEN" "============================================"
print_message "$GREEN" "Building Optimized RAG Service Docker Image"
print_message "$GREEN" "============================================"
echo ""

# Change to rag-service directory
cd "$(dirname "$0")"

print_message "$YELLOW" "Image: ${REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}"
print_message "$YELLOW" "Platform: linux/amd64"
echo ""

# Build the Docker image
print_message "$GREEN" "Building Docker image..."
docker build \
    --platform linux/amd64 \
    -t "${REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}" \
    -f Dockerfile \
    .

if [ $? -eq 0 ]; then
    print_message "$GREEN" "✓ Docker image built successfully!"
    echo ""
    print_message "$GREEN" "Image details:"
    docker images "${REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}"
    echo ""
    
    print_message "$YELLOW" "To use this image, update your Neovim config:"
    echo ""
    echo "  rag_service = {"
    echo "    enabled = true,"
    echo "    image = \"${REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}\","
    echo "    docker_extra_args = \"--gpus all\",  -- Enable GPU access"
    echo "    -- ... rest of config"
    echo "  }"
    echo ""
    
    if [ -n "$REGISTRY" ]; then
        print_message "$YELLOW" "To push to registry:"
        echo "  docker push ${REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}"
        echo ""
    fi
    
    print_message "$GREEN" "To test the image locally:"
    echo "  docker run --rm -p 20250:20250 \\"
    echo "    -e RAG_EMBED_PROVIDER=ollama \\"
    echo "    -e RAG_EMBED_ENDPOINT=http://host.docker.internal:11434 \\"
    echo "    -e RAG_EMBED_MODEL=nomic-embed-text \\"
    echo "    -e RAG_LLM_PROVIDER=ollama \\"
    echo "    -e RAG_LLM_ENDPOINT=http://host.docker.internal:11434 \\"
    echo "    -e RAG_LLM_MODEL=llama3.2 \\"
    echo "    ${REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}"
    echo ""
else
    print_message "$RED" "✗ Docker build failed!"
    exit 1
fi

