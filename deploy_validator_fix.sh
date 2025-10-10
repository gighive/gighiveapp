#!/bin/bash

# Deploy updated UploadValidator.php to server

SERVER="ubuntu@gighive"
LOCAL_FILE="$HOME/scripts/gighive/ansible/roles/docker/files/apache/webroot/src/Validation/UploadValidator.php"
REMOTE_FILE="/var/www/html/src/Validation/UploadValidator.php"

echo "📦 Deploying UploadValidator.php fix to $SERVER"
echo "================================================"
echo ""

# 1. Copy file to server
echo "1️⃣ Copying updated file to server..."
scp "$LOCAL_FILE" "$SERVER:/tmp/UploadValidator.php"

echo ""
echo ""

# 2. Copy into container
echo "2️⃣ Copying file into Docker container..."
ssh $SERVER "docker cp /tmp/UploadValidator.php apacheWebServer:$REMOTE_FILE"

echo ""
echo ""

# 3. Set permissions
echo "3️⃣ Setting correct permissions..."
ssh $SERVER "docker exec apacheWebServer chown www-data:www-data $REMOTE_FILE"

echo ""
echo ""

# 4. Verify content
echo "4️⃣ Verifying file content..."
ssh $SERVER "docker exec apacheWebServer grep -n 'defaultMax = 6 \* 1024' $REMOTE_FILE"

echo ""
echo ""

# 5. Clear OPcache
echo "5️⃣ Clearing OPcache..."
ssh $SERVER "docker exec apacheWebServer php -r 'opcache_reset();'"

echo ""
echo ""

# 6. Restart PHP-FPM
echo "6️⃣ Restarting PHP-FPM..."
ssh $SERVER "docker exec apacheWebServer service php8.1-fpm restart"

echo ""
echo ""

# 7. Test the new value
echo "7️⃣ Testing validator limit..."
ssh $SERVER "docker exec apacheWebServer php -r \"
require_once '/var/www/html/vendor/autoload.php';
\\\$validator = new \Production\Api\Validation\UploadValidator();
\\\$reflection = new ReflectionClass(\\\$validator);
\\\$property = \\\$reflection->getProperty('maxBytes');
\\\$property->setAccessible(true);
echo 'Current maxBytes: ' . number_format(\\\$property->getValue(\\\$validator)) . ' bytes' . PHP_EOL;
echo 'Expected: 6,442,450,944 bytes (6 GB)' . PHP_EOL;
\""

echo ""
echo ""
echo "✅ Deployment complete! Try uploading again."
