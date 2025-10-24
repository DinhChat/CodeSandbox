# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version
* 3.4.5

* Create Docker image
docker build -t code_sandbox .

* Run Docker container
docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name code_sandbox code_sandbox

* Check Docker container
docker images
docker ps -a
docker exec -it <container_name_or_id> /bin/bash
docker logs -f <container_name_or_id>
