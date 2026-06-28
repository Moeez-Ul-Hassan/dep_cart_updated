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

# 3. Start the target service (Using the SERVICE name)
docker compose -f docker-compose.prod.yml up -d --no-deps $NEW_SERVICE

# 4. THE ENTERPRISE HEALTH CHECK
echo "Waiting for $NEW_CONTAINER to initialize..."
sleep 5

HEALTH_CHECK_PASSED=false
for i in {1..5}; do
    # Execute curl INSIDE the new container (Using the CONTAINER name)
    if docker exec $NEW_CONTAINER curl -sSf http://localhost:8000/docs > /dev/null; then
        echo "✅ Health check passed! $NEW_CONTAINER is alive."
        HEALTH_CHECK_PASSED=true
        break
    fi
    echo "⏳ Waiting for $NEW_CONTAINER... ($i/5)"
    sleep 3
done

# If it failed, abort the deployment and keep the old container running
if [ "$HEALTH_CHECK_PASSED" = false ]; then
    echo "❌ FATAL: $NEW_CONTAINER failed health check!"
    echo "Aborting deployment. Rolling back to $OLD_CONTAINER."
    # Destroy the broken service
    docker compose -f docker-compose.prod.yml stop $NEW_SERVICE
    docker compose -f docker-compose.prod.yml rm -f $NEW_SERVICE
    exit 1
fi

# 5. Swap the Nginx configuration to point to the new container
sed -i "s/server cart_fastapi_blue:8000;/server $NEW_CONTAINER:8000;/g" nginx/nginx.conf
sed -i "s/server cart_fastapi_green:8000;/server $NEW_CONTAINER:8000;/g" nginx/nginx.conf

# 6. Hard Restart Nginx (Fixes the 502 IP caching bug)
echo "Restarting Nginx to flush DNS cache..."
docker restart cart_nginx

echo "Success! Nginx is now routing all traffic to $NEW_CONTAINER."

# 7. Safely shut down the old service
docker compose -f docker-compose.prod.yml stop $OLD_SERVICE
echo "Deployment complete. $OLD_CONTAINER has been deactivated."