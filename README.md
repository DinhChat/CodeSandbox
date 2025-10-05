# README

How to build Docker environment for this service:

cd /home/dinhchat/Project/Code_Sandbox
sudo docker build -t code_sandbox-app:latest .
sudo docker run -d -p 3000:80 -v /var/run/docker.sock:/var/run/docker.sock --name code_sandbox code_sandbox-app:latest

kiem tra 