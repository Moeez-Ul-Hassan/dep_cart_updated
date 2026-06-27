#!/bin/bash

echo "Starting Zero-Downtime Deployment..."

# 1. Ask Docker directly which container is currently running
if [ "$(docker ps -q -f name=cart_fastapi_blue)" ]; then
    OLD="web_blue"
    TARGET="web_green"
else
    OLD="web_green"
    TARGET="web_blue"
fi

echo "Current active container is $OLD. Deploying update to $TARGET..."

# 2. Pull the latest image from Docker Hub
docker compose -f docker-compose.prod.yml pull

# 3. Start the target container in the background
docker compose -f docker-compose.prod.yml up -d --no-deps $TARGET

# 4. Wait for it to boot up and be healthy
echo "Waiting 10 seconds for $TARGET to initialize..."
sleep 10

# 5. Swap the Nginx configuration to point to the new container
# We aggressively replace both possible states just to be perfectly safe
sed -i "s/proxy_pass http:\/\/web_blue:8000;/proxy_pass http:\/\/$TARGET:8000;/g" nginx/nginx.conf
sed -i "s/proxy_pass http:\/\/web_green:8000;/proxy_pass http:\/\/$TARGET:8000;/g" nginx/nginx.conf

# 6. Graceful Reload: Nginx shifts traffic instantly without dropping users
docker exec cart_nginx nginx -s reload
echo "Success! Nginx is now routing all traffic to $TARGET."

# 7. Safely shut down the old container
docker compose -f docker-compose.prod.yml stop $OLD
echo "Deployment complete. $OLD has been deactivated."