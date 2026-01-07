#!/bin/bash
# build-modules.sh - Fetches and builds modules from the registry
#
# Usage: ./build-modules.sh [options]
#
# Options:
#   -r, --registry-url URL    URL to registry.yaml (default: $MODULE_REGISTRY_URL)
#   -o, --output-dir DIR      Output directory for modules (default: ./modules)
#   -m, --manifest-path PATH  Path for generated manifest (default: ./registry-manifest.json)
#   -t, --token TOKEN         GitHub token for private repos (default: $GITHUB_TOKEN)
#   -v, --verbose             Enable verbose output
#   -h, --help                Show this help message
#
# Environment variables:
#   MODULE_REGISTRY_URL       Default registry URL
#   GITHUB_TOKEN              GitHub token for private repo access
#
# Exit codes:
#   0 - Build successful
#   1 - Build failed

set -euo pipefail

# Default values
REGISTRY_URL="${MODULE_REGISTRY_URL:-}"
OUTPUT_DIR="./modules"
MANIFEST_PATH="./registry-manifest.json"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
VERBOSE=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_info() {
    echo -e "${BLUE}INFO:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "  $1"
    fi
}

show_help() {
    cat << EOF
build-modules.sh - Fetches and builds modules from the registry

Usage: $0 [options]

Options:
  -r, --registry-url URL    URL to registry.yaml (default: \$MODULE_REGISTRY_URL)
  -o, --output-dir DIR      Output directory for modules (default: ./modules)
  -m, --manifest-path PATH  Path for generated manifest (default: ./registry-manifest.json)
  -t, --token TOKEN         GitHub token for private repos (default: \$GITHUB_TOKEN)
  -v, --verbose             Enable verbose output
  -h, --help                Show this help message

Environment variables:
  MODULE_REGISTRY_URL       Default registry URL
  GITHUB_TOKEN              GitHub token for private repo access

Example:
  $0 -r https://raw.githubusercontent.com/org/registry/main/registry.yaml
  $0 -r https://example.com/registry.yaml -t ghp_xxxxxxxxxxxx
  MODULE_REGISTRY_URL=https://example.com/registry.yaml $0
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--registry-url)
            REGISTRY_URL="$2"
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -m|--manifest-path)
            MANIFEST_PATH="$2"
            shift 2
            ;;
        -t|--token)
            GITHUB_TOKEN="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate registry URL
if [ -z "$REGISTRY_URL" ]; then
    log_error "Registry URL not provided. Use -r option or set MODULE_REGISTRY_URL environment variable."
    exit 1
fi

log_info "Starting module build process"
log_info "Registry URL: $REGISTRY_URL"
log_info "Output directory: $OUTPUT_DIR"
log_info "Manifest path: $MANIFEST_PATH"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Fetch registry.yaml
log_info "Fetching registry.yaml..."
REGISTRY_FILE=$(mktemp)
trap "rm -f $REGISTRY_FILE" EXIT

if ! curl -sSfL "$REGISTRY_URL" -o "$REGISTRY_FILE"; then
    log_error "Failed to fetch registry.yaml from $REGISTRY_URL"
    exit 1
fi
log_success "Registry fetched successfully"

# Check if yq is available for YAML parsing
if ! command -v yq &> /dev/null; then
    log_error "yq is required but not installed. Install with: brew install yq (macOS) or snap install yq (Linux)"
    exit 1
fi

# Initialize manifest JSON
MANIFEST_TEMP=$(mktemp)
echo '{"schemaVersion":"1.0","generatedAt":"'"$(date -u +"%Y-%m-%dT%H:%M:%SZ")"'","modules":[]}' > "$MANIFEST_TEMP"

# Parse registry and process each approved module
log_info "Processing modules from registry..."
MODULE_COUNT=0
FAILED_COUNT=0

# Get list of approved modules
MODULES=$(yq e '.modules[] | select(.status == "approved") | .id' "$REGISTRY_FILE" 2>/dev/null || echo "")

if [ -z "$MODULES" ]; then
    log_warning "No approved modules found in registry"
else
    while IFS= read -r MODULE_ID; do
        if [ -z "$MODULE_ID" ]; then
            continue
        fi
        
        log_info "Processing module: $MODULE_ID"
        
        # Extract module details
        REPO_URL=$(yq e ".modules[] | select(.id == \"$MODULE_ID\") | .repoUrl" "$REGISTRY_FILE")
        VERSION=$(yq e ".modules[] | select(.id == \"$MODULE_ID\") | .version" "$REGISTRY_FILE")
        AUTHOR=$(yq e ".modules[] | select(.id == \"$MODULE_ID\") | .author" "$REGISTRY_FILE")
        AUTHOR_TYPE=$(yq e ".modules[] | select(.id == \"$MODULE_ID\") | .authorType" "$REGISTRY_FILE")
        
        log_verbose "  Repo: $REPO_URL"
        log_verbose "  Version: $VERSION"
        log_verbose "  Author: $AUTHOR ($AUTHOR_TYPE)"
        
        # Build authenticated URL if token is provided
        CLONE_URL="$REPO_URL"
        if [ -n "$GITHUB_TOKEN" ]; then
            # Convert https://github.com/org/repo to https://token@github.com/org/repo
            CLONE_URL=$(echo "$REPO_URL" | sed "s|https://github.com|https://${GITHUB_TOKEN}@github.com|")
            log_verbose "  Using authenticated clone URL"
        fi
        
        # Clone module at specific version
        MODULE_DIR="$OUTPUT_DIR/$MODULE_ID"
        
        if [ -d "$MODULE_DIR" ]; then
            log_verbose "  Removing existing directory..."
            rm -rf "$MODULE_DIR"
        fi
        
        log_verbose "  Cloning repository..."
        if [ "$VERSION" = "latest" ]; then
            log_warning "Module $MODULE_ID uses 'latest' version - builds may not be reproducible"
            if ! git clone --quiet --depth 1 "$CLONE_URL" "$MODULE_DIR" 2>/dev/null; then
                log_error "Failed to clone $MODULE_ID at latest"
                FAILED_COUNT=$((FAILED_COUNT + 1))
                continue
            fi
            # Capture actual commit SHA for manifest
            ACTUAL_VERSION=$(git -C "$MODULE_DIR" rev-parse --short HEAD 2>/dev/null || echo "latest")
        else
            if ! git clone --quiet --depth 1 --branch "$VERSION" "$CLONE_URL" "$MODULE_DIR" 2>/dev/null; then
                log_error "Failed to clone $MODULE_ID at version $VERSION"
                FAILED_COUNT=$((FAILED_COUNT + 1))
                continue
            fi
            ACTUAL_VERSION="$VERSION"
        fi
        
        # Remove .git directory to save space
        rm -rf "$MODULE_DIR/.git"
        
        # Validate module
        log_verbose "  Validating module..."
        if ! "$SCRIPT_DIR/validate-module.sh" "$MODULE_DIR" > /dev/null 2>&1; then
            log_error "Module validation failed for $MODULE_ID"
            rm -rf "$MODULE_DIR"
            FAILED_COUNT=$((FAILED_COUNT + 1))
            continue
        fi
        
        # Add to manifest
        CLONED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        
        # Use jq to add module to manifest
        if command -v jq &> /dev/null; then
            jq --arg id "$MODULE_ID" \
               --arg version "$ACTUAL_VERSION" \
               --arg requestedVersion "$VERSION" \
               --arg author "$AUTHOR" \
               --arg authorType "$AUTHOR_TYPE" \
               --arg repoUrl "$REPO_URL" \
               --arg clonedAt "$CLONED_AT" \
               '.modules += [{"id":$id,"version":$version,"requestedVersion":$requestedVersion,"author":$author,"authorType":$authorType,"repoUrl":$repoUrl,"clonedAt":$clonedAt}]' \
               "$MANIFEST_TEMP" > "${MANIFEST_TEMP}.new" && mv "${MANIFEST_TEMP}.new" "$MANIFEST_TEMP"
        else
            log_warning "jq not available - manifest may be incomplete"
        fi
        
        log_success "Module $MODULE_ID cloned and validated"
        MODULE_COUNT=$((MODULE_COUNT + 1))
        
    done <<< "$MODULES"
fi

# Write final manifest
mv "$MANIFEST_TEMP" "$MANIFEST_PATH"
log_success "Manifest written to $MANIFEST_PATH"

# Summary
echo ""
echo "================================"
echo "Build Summary"
echo "================================"
echo "Modules processed: $MODULE_COUNT"
echo "Modules failed: $FAILED_COUNT"

if [ $FAILED_COUNT -gt 0 ]; then
    log_error "Build completed with $FAILED_COUNT failure(s)"
    exit 1
else
    log_success "Build completed successfully"
    exit 0
fi
