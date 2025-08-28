#!/bin/bash
# Clean extended attributes from System Extension before code signing

EXTENSION_PATH="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.systemextension"

if [ -d "$EXTENSION_PATH" ]; then
    echo "Cleaning extended attributes from: $EXTENSION_PATH"
    xattr -cr "$EXTENSION_PATH"
    find "$EXTENSION_PATH" -name ".DS_Store" -delete
fi