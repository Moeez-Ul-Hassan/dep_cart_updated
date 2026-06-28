#!/bin/bash
echo "Starting Zero-Downtime Deployment..."

# 1. Ask Docker directly which container is currently running
if [ "$(docker ps -q -f name=cart_fastapi_blue)" ]; then
    OLD="cart_fastapi_blue"
    TARGET="cart_fastapi_green"
else
    OLD="cart_fastapi_green"
    TARGET="cart_fastapi_blue"
fi

echo "Current active container is $OLD. Deploying update to $TARGET..."

# 2. Pull the latest image from Docker Hub
docker compose -f docker-compose.prod.yml pull

# 3. Start the target container in the background
docker compose -f docker-compose.prod.yml up -d --no-deps $TARGET

# 4. THE ENTERPRISE HEALTH CHECK
echo "Waiting for $TARGET to initialize..."
sleep 5

HEALTH_CHECK_PASSED=false
for i in {1..5}; do
    # Execute curl INSIDE the new container to see if FastAPI is answering
    if docker exec $TARGET curl -sSf http://localhost:8000/docs > /dev/null; then
        echo "✅ Health check passed! $TARGET is alive."
        HEALTH_CHECK_PASSED=true
        break
    fi
    echo "⏳ Waiting for $TARGET... ($i/5)"
    sleep 3
done

# If it failed, abort the deployment and keep the old container running
if [ "$HEALTH_CHECK_PASSED" = false ]; then
    echo "❌ FATAL: $TARGET failed health check (Crash on startup)!"
    echo "Aborting deployment. Rolling back to $OLD."
    docker stop $TARGET
    docker rm $TARGET
    exit 1
fi

# 5. Swap the Nginx configuration to point to the new container
sed -i "s/server cart_fastapi_blue:8000;/server $TARGET:8000;/g" nginx/nginx.conf
sed -i "s/server cart_fastapi_green:8000;/server $TARGET:8000;/g" nginx/nginx.conf

# 6. Hard Restart Nginx (Fixes the 502 IP caching bug)
echo "Restarting Nginx to flush DNS cache..."
docker restart cart_nginx

echo "Success! Nginx is now routing all traffic to $TARGET."

# 7. Safely shut down the old container
docker compose -f docker-compose.prod.yml stop $OLD
echo "Deployment complete. $OLD has been deactivated."