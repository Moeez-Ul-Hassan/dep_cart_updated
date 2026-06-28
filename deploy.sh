#!/bin/bash
echo "Starting Zero-Downtime Deployment..."

# 1. Determine active environments
if [ "$(docker ps -q -f name=cart_fastapi_blue)" ]; then
    OLD_SERVICE="web_blue"
    OLD_CONTAINER="cart_fastapi_blue"
    
    NEW_SERVICE="web_green"
    NEW_CONTAINER="cart_fastapi_green"
else
    OLD_SERVICE="web_green"
    OLD_CONTAINER="cart_fastapi_green"
    
    NEW_SERVICE="web_blue"
    NEW_CONTAINER="cart_fastapi_blue"
fi

echo "Current active container is $OLD_CONTAINER. Deploying update to $NEW_CONTAINER..."

# 2. Pull the latest image from Docker Hub
docker compose -f docker-compose.prod.yml pull

# 3. Start the target service
docker compose -f docker-compose.prod.yml up -d --no-deps $NEW_SERVICE

# 4. THE ENTERPRISE HEALTH CHECK
echo "Waiting for $NEW_CONTAINER to initialize..."
sleep 5

HEALTH_CHECK_PASSED=false
for i in {1..5}; do
    if docker exec $NEW_CONTAINER python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/docs')" 2>/dev/null; then
        echo "✅ Health check passed! $NEW_CONTAINER is alive."
        HEALTH_CHECK_PASSED=true
        break
    fi
    echo "⏳ Waiting for $NEW_CONTAINER... ($i/5)"
    sleep 3
done

if [ "$HEALTH_CHECK_PASSED" = false ]; then
    echo "❌ FATAL: $NEW_CONTAINER failed health check!"
    echo "--- START CRASH LOGS ---"
    docker logs $NEW_CONTAINER
    echo "--- END CRASH LOGS ---"
    echo "Aborting deployment. Rolling back to $OLD_CONTAINER."
    
    docker compose -f docker-compose.prod.yml stop $NEW_SERVICE
    docker compose -f docker-compose.prod.yml rm -f $NEW_SERVICE
    exit 1
fi

# 5. Swap the Nginx configuration (THE FIX)
sed -i "s/web_blue:8000/$NEW_SERVICE:8000/g" nginx/nginx.conf
sed -i "s/web_green:8000/$NEW_SERVICE:8000/g" nginx/nginx.conf

# 6. Hard Restart Nginx
echo "Restarting Nginx to flush DNS cache..."
docker restart cart_nginx

echo "Success! Nginx is now routing all traffic to $NEW_CONTAINER."

# 7. Safely shut down the old service
docker compose -f docker-compose.prod.yml stop $OLD_SERVICE
echo "Deployment complete. $OLD_CONTAINER has been deactivated."