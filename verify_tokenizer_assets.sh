#!/bin/bash

# Build phase script to verify required tokenizer assets are bundled
# This should be added as a "Run Script" build phase in Xcode

set -e

echo "🔍 Verifying tokenizer assets are bundled..."

BUNDLE_RESOURCES_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app"
ML_ASSETS_DIR="${BUNDLE_RESOURCES_DIR}/ios_integration_assets"

# Required tokenizer assets
REQUIRED_ASSETS=(
    "vocab.json"
    "merges.txt" 
    "id_to_token.json"
    "tokenizer_config.json"
    "special_tokens_map.json"
    "added_tokens.json"
)

MISSING_ASSETS=()

for asset in "${REQUIRED_ASSETS[@]}"; do
    if [[ ! -f "${ML_ASSETS_DIR}/${asset}" ]]; then
        MISSING_ASSETS+=("${asset}")
    else
        echo "✅ Found: ${asset}"
    fi
done

if [[ ${#MISSING_ASSETS[@]} -gt 0 ]]; then
    echo ""
    echo "❌ ERROR: Missing required tokenizer assets:"
    for asset in "${MISSING_ASSETS[@]}"; do
        echo "   - ${asset}"
    done
    echo ""
    echo "These files must be present in the app bundle for the BPE tokenizer to work."
    echo "Add them to your project and ensure they have target membership."
    echo "Expected location: ${ML_ASSETS_DIR}/"
    echo ""
    exit 1
fi

echo "✅ All required tokenizer assets are bundled correctly!"
