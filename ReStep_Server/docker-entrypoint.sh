#!/bin/sh
set -e

if [ -f "composer.json" ]; then
    if [ ! -d "vendor" ]; then
        echo "Installing Composer dependencies..."
        composer install --no-interaction --optimize-autoloader
    fi
fi

exec "$@"
