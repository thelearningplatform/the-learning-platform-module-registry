#!/bin/bash
# validate-module.sh - Validates a learning module's structure and required files
#
# Usage: ./validate-module.sh <module-path>
#
# Exit codes:
#   0 - Validation passed
#   1 - Validation failed
#
# Requirements validated:
#   - track.yaml exists with required fields
#   - Module directories follow naming convention
#   - Step directories have required files

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validation counters
ERRORS=0
WARNINGS=0

log_error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
    ((ERRORS++))
}

log_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1" >&2
    ((WARNINGS++))
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_info() {
    echo -e "  $1"
}

# Check if module path is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <module-path>"
    echo "Example: $0 ./modules/gpu-programming"
    exit 1
fi

MODULE_PATH="$1"

# Verify module directory exists
if [ ! -d "$MODULE_PATH" ]; then
    log_error "Module directory does not exist: $MODULE_PATH"
    exit 1
fi

echo "Validating module: $MODULE_PATH"
echo "================================"

# 1. Validate track.yaml exists
TRACK_YAML="$MODULE_PATH/track.yaml"
if [ ! -f "$TRACK_YAML" ]; then
    log_error "track.yaml not found at $TRACK_YAML"
else
    log_success "track.yaml exists"
    
    # Check required fields in track.yaml
    # Using grep for basic validation (yq would be better but may not be available)
    if grep -q "^id:" "$TRACK_YAML"; then
        log_success "track.yaml has 'id' field"
    else
        log_error "track.yaml missing required 'id' field"
    fi
    
    if grep -q "^name:" "$TRACK_YAML"; then
        log_success "track.yaml has 'name' field"
    else
        log_error "track.yaml missing required 'name' field"
    fi
    
    if grep -q "^description:" "$TRACK_YAML"; then
        log_success "track.yaml has 'description' field"
    else
        log_error "track.yaml missing required 'description' field"
    fi
    
    if grep -q "^modules:" "$TRACK_YAML"; then
        log_success "track.yaml has 'modules' section"
    else
        log_error "track.yaml missing required 'modules' section"
    fi
fi

# 2. Validate module directories
echo ""
echo "Checking module directories..."
echo "------------------------------"

# Find all module directories (directories containing module.yaml)
MODULE_DIRS=$(find "$MODULE_PATH" -name "module.yaml" -exec dirname {} \; 2>/dev/null || true)

if [ -z "$MODULE_DIRS" ]; then
    log_warning "No module.yaml files found - this may be a track without modules"
else
    for MODULE_DIR in $MODULE_DIRS; do
        MODULE_NAME=$(basename "$MODULE_DIR")
        log_info "Checking module: $MODULE_NAME"
        
        # Check module.yaml has required fields
        MODULE_YAML="$MODULE_DIR/module.yaml"
        if grep -q "^id:" "$MODULE_YAML"; then
            log_success "  module.yaml has 'id' field"
        else
            log_error "  module.yaml missing 'id' field in $MODULE_DIR"
        fi
        
        if grep -q "^name:" "$MODULE_YAML"; then
            log_success "  module.yaml has 'name' field"
        else
            log_error "  module.yaml missing 'name' field in $MODULE_DIR"
        fi
        
        # Check naming convention (lowercase with hyphens)
        if [[ "$MODULE_NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
            log_success "  Directory name follows convention: $MODULE_NAME"
        else
            log_warning "  Directory name should be lowercase with hyphens: $MODULE_NAME"
        fi
    done
fi

# 3. Validate step directories
echo ""
echo "Checking step directories..."
echo "----------------------------"

# Find all step directories (directories containing step.yaml)
STEP_DIRS=$(find "$MODULE_PATH" -name "step.yaml" -exec dirname {} \; 2>/dev/null || true)

if [ -z "$STEP_DIRS" ]; then
    log_warning "No step.yaml files found - this may be a track without steps"
else
    for STEP_DIR in $STEP_DIRS; do
        STEP_NAME=$(basename "$STEP_DIR")
        log_info "Checking step: $STEP_NAME"
        
        STEP_YAML="$STEP_DIR/step.yaml"
        
        # Check step.yaml has required fields
        if grep -q "^id:" "$STEP_YAML"; then
            log_success "  step.yaml has 'id' field"
        else
            log_error "  step.yaml missing 'id' field in $STEP_DIR"
        fi
        
        if grep -q "^name:" "$STEP_YAML"; then
            log_success "  step.yaml has 'name' field"
        else
            log_error "  step.yaml missing 'name' field in $STEP_DIR"
        fi
        
        # Check for content file (instructions.md or similar)
        if [ -f "$STEP_DIR/explanation.md" ] || [ -f "$STEP_DIR/instructions.md" ] || [ -f "$STEP_DIR/content.md" ] || [ -f "$STEP_DIR/README.md" ]; then
            log_success "  Step has content file"
        else
            log_warning "  Step missing content file (explanation.md, instructions.md, content.md, or README.md)"
        fi
    done
fi

# 4. Summary
echo ""
echo "================================"
echo "Validation Summary"
echo "================================"

if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}FAILED${NC}: $ERRORS error(s), $WARNINGS warning(s)"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}PASSED WITH WARNINGS${NC}: $WARNINGS warning(s)"
    exit 0
else
    echo -e "${GREEN}PASSED${NC}: All validations successful"
    exit 0
fi
