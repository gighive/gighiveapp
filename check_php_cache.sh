#!/bin/bash

# Script to check and clear PHP caching issues
# Run this directly on the Docker host (ubuntu@gighive)

echo "🔍 Checking PHP Cache Status"
echo "=============================="
echo ""

# 1. Check if OPcache is enabled
echo "1️⃣ Checking OPcache status..."
docker exec apacheWebServer php -i | grep -E 'opcache.enable|opcache.revalidate_freq'

echo ""
echo ""

# 2. Check current validator value in running PHP
echo "2️⃣ Testing current validator limit via PHP..."
docker exec apacheWebServer php -r "
require_once '/var/www/html/vendor/autoload.php';
\$validator = new \Production\Api\Validation\UploadValidator();
\$reflection = new ReflectionClass(\$validator);
\$property = \$reflection->getProperty('maxBytes');
\$property->setAccessible(true);
echo 'Current maxBytes: ' . number_format(\$property->getValue(\$validator)) . ' bytes' . PHP_EOL;
echo 'Expected: 6,442,450,944 bytes (6 GB)' . PHP_EOL;
"

echo ""
echo ""

# 3. Clear OPcache
echo "3️⃣ Clearing OPcache..."
docker exec apacheWebServer php -r "opcache_reset();" 2>/dev/null && echo "✅ OPcache cleared" || echo "⚠️ OPcache not available or already disabled"

echo ""
echo ""

# 4. Restart PHP-FPM
echo "4️⃣ Restarting PHP-FPM..."
docker exec apacheWebServer service php8.1-fpm restart

echo ""
echo ""

# 5. Verify file content again
echo "5️⃣ Verifying file content..."
docker exec apacheWebServer grep -n 'maxBytes.*6_' /var/www/html/src/Validation/UploadValidator.php

echo ""
echo ""

# 6. Test again
echo "6️⃣ Testing validator limit again after restart..."
docker exec apacheWebServer php -r "
require_once '/var/www/html/vendor/autoload.php';
\$validator = new \Production\Api\Validation\UploadValidator();
\$reflection = new ReflectionClass(\$validator);
\$property = \$reflection->getProperty('maxBytes');
\$property->setAccessible(true);
echo 'Current maxBytes: ' . number_format(\$property->getValue(\$validator)) . ' bytes' . PHP_EOL;
echo 'Expected: 6,442,450,944 bytes (6 GB)' . PHP_EOL;
"

echo ""
echo ""
echo "✅ Done! Try uploading again."
