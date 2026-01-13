# README

# Ruby version: 3.4.5

# How to build ruby on rails environment:
## Ubuntu:
```bash
sudo apt update
sudo apt install build-essential rustc libssl-dev libyaml-dev zlib1g-dev libgmp-dev git
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate)"' >> ~/.bashrc
source ~/.bashrc
mise use -g ruby@3.4.5

gem install rails
```

## RHEL:
```bash
yum install -y gcc-c++ patch readline readline-devel \
    zlib zlib-devel libyaml-devel libffi-devel openssl-devel \
    make bzip2 autoconf automake libtool bison sqlite-devel

git clone https://github.com/rbenv/rbenv.git ~/.rbenv
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bash_profile
echo 'eval "$(rbenv init -)"' >> ~/.bash_profile
source ~/.bash_profile

git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build

rbenv install 3.4.5

gem install rails -v 8.0
```
# How to build environment for this service:
```bash
install docker
find docker gid -> add user run service to the docker group: usermod -aG docker $USER
restart user session
```

# Run service:
```bash
cd /CodeSandbox
bundle íntall
rails s
```

# Case run service in KVM/QEMU: Mount folder
```bash
sudo mkdir -p /mnt/shared
sudo mount -t virtiofs project /mnt/shared
```

## Dockerfile for cpp: Dockerfile.cpp
```bash
# Dockerfile.cpp
FROM gcc:12-bookworm

RUN apt-get update -y && apt-get install -y jq bc && rm -rf /var/lib/apt/lists/*

WORKDIR /app
```

### Dockerfile for python: Dockerfile.py
```bash
FROM python:3.12-slim-bookworm

RUN apt-get update -y \
    && apt-get install -y jq bc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
```
# build docker images:
```bash
docker build -f Dockerfile.cpp -t my-cpp-executor:12 .
```




