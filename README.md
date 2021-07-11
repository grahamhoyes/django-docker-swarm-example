# Django Docker Swarm Example
An example project for deploying Django on Docker Swarm.

Read the full documentation with a detailed walkthrough at https://django-docker-swarm-example.readthedocs.io/en/latest/.

This is primarily a playground and documentation for [IEEE UofT's](https://ieee.utoronto.ca/) deployment needs to serve our [hackathon template](https://github.com/ieeeuoft/hackathon-template). As such, the requirements are:
- Runs on a single server, but the option to add more nodes in the future is preferred
- Postgres is installed natively on the server
- Nginx is installed natively on the server, handling SSL and static file serving. We were using Apache, but after trying to get the reverse proxy for this tutorial to work properly we gave up and switched to Nginx. Would recommend.
- The application should be deployed as a docker container that Apache/Nginx can reverse proxy to

This project walks through installing a postgres server, nginx, docker engine, and initializing Docker Swarm on a single machine (i.e., we will be creating a Swarm cluster with a single node). 

This project does not:
- Use [Docker Machine](https://docs.docker.com/machine/), because my use case is running on an existing server.
- Expose the Docker API. All remote connections will be made over SSH.

## Credits
The following resources were a great help in developing this example:
- https://github.com/testdrivenio/django-github-digitalocean
- https://docs.github.com/en/packages/using-github-packages-with-your-projects-ecosystem/configuring-docker-for-use-with-github-packages
- https://github.com/appleboy/scp-action
- https://github.com/appleboy/ssh-action
- https://stackoverflow.com/questions/47941075/host-django-on-subfolder/47945170#47945170
