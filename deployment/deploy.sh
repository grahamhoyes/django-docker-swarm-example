#!/bin/bash
github_actor=$1
github_token=$2
stack_name=$3

curl -s https://raw.githubusercontent.com/sudo-bmitch/docker-stack-wait/main/docker-stack-wait.sh \
  -o docker-stack-wait.sh
chmod +x docker-stack-wait.sh

echo $github_token | docker login docker.pkg.github.com -u $github_actor --password-stdin
docker stack deploy --with-registry-auth -c docker-compose.prod.yml $stack_name

echo "Waiting for deployment..."
./docker-stack-wait.sh $stack_name

echo "Running migrations..."
# TODO: This will fail if at least one replica isn't running on the node, will need to
# switch DOCKER_HOST over ssh
service_id=$(docker ps -f "name=${stack_name}_django" -q | head -n1)
docker exec $service_id python manage.py migrate

echo "Cleaning up..."
rm .env
rm docker-stack-wait.sh
docker logout docker.pkg.github.com

echo "Deployment complete"
