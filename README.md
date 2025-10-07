# README

# How to build Docker environment for this service:
cd /home/dinhchat/Project/Code_Sandbox
docker build -t code_sandbox-app:latest .
docker run -d -p 3000:3000 -e RAILS_MASTER_KEY=0a5f37f35ea51647540ff71f48cdd73f -v /var/run/docker.sock:/var/run/docker.sock --name code_sandbox code_sandbox-app:latest
docker images

# Check container
docker ps 
docker ps a
docker exec -it code_sandbox /bin/bash

# stop/start container
docker stop code_sandbox
docker start code_sandbox

