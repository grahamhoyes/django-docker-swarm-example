# Django Docker Swarm Example
An example project for deploying Django on Docker Swarm.

This is primarily a playground and documentation for [IEEE UofT's](https://ieee.utoronto.ca/) deployment needs to server our [hackathon template](https://github.com/ieeeuoft/hackathon-template). As such, the requirements are:
- Runs on a single server, but the option to add more nodes in the future is preferred
- Postgres is installed natively on the server
- Nginx is installed natively on the server, handling SSL and static file serving. We were using Apache, but after trying to get the reverse proxy for this tutorial to work properly we gave up and switched to Nginx. Would recommend.
- The application should be deployed as a docker container that Apache/Nginx can reverse proxy to
- Multiple independent instances must be possible (for multiple events)
- Applications must be able to run under a sub-folder of the website, i.e. ieee.utoronto.ca/event1, ieee.utoronto.ca/event2

This project walks through installing a postgres server, docker engine, and initializing Docker Swarm on a single machine (i.e., we will be creating a Swarm cluster with a single node). 

This project does not:
- Use [Docker Machine](https://docs.docker.com/machine/), because my use case is running on an existing server.
- Expose the Docker API. All remote connections will be made over SSH.

## Credits
The following resources were a great help in developing this example:
- https://github.com/testdrivenio/django-github-digitalocean
- https://docs.github.com/en/packages/using-github-packages-with-your-projects-ecosystem/configuring-docker-for-use-with-github-packages
- https://github.com/appleboy/scp-action
- https://github.com/appleboy/ssh-action

## Running locally
Configurations for running locally are within the [development](development) folder.

To build the container, from within the repository root:

```bash
$ docker-compose -f development/docker-compose.yml build
```

Note: [development/docker-compose.yml](development/docker-compose.yml) sets the build context for the django service to `..` relative to the `development` folder, i.e. the repository root. [development/Dockerfile](development/Dockerfile) is hence written with all paths relative to the repository root.

To run the project:

```bash
$ docker-compose -f development/docker-compose.yml up
```

This will start the postgres and django containers, the latter of which will wait for postgres to be available (via the [entrypoint.sh](development/entrypoint.sh)). The django service will run migrations as soon as the postgres connection is established.

Once both containers are up, you can access the server at http://localhost:8000/. The first time you visit, you should see `{"hits": 1}`. The counter will increase with every subsequent visit.

## Deployment Setup
Create a server using your cloud provider of choice. For this example, I am using a Digital Ocean droplet running Ubuntu 18.04 with 1 GB of RAM and 1 vCPU. 

SSH into the machine, and follow the steps below. Note that we assume you will be running the deployments using the user you ssh in with. If you wish to use a dedicated user for automated deploys, ssh in with that user below. The user must have docker privileges.

### Install Docker
Install Docker Engine by following the steps in the [Docker documentation](https://docs.docker.com/engine/install/ubuntu/).

#### Credentials Setup
In order to pull images from GitHub packages, we will need to run `docker login` as part of the deployment process. We will be using Docker's default credentials configuration for simplicity, which is to store credentials in plain text in `~/.docker/config.json`. 

In order for credentials to work, we still need to install gnupg2 and [pass](https://www.passwordstore.org/):

```bash
$ sudo apt install gnupg2 pass 
```

If you would like to continue setting up a proper credentials store, you can read about [credentials stores](https://docs.docker.com/engine/reference/commandline/login/#credentials-store). If you have confidence in the security of the server you are deploying to such that nobody can access the plaintext credentials, you may skip this step, but it is recommended to have a secure credentials store.

### Create the Swarm
In this example, we will be working on a single-node swarm. For a full example of how to create a swarm and attach worker nodes, follow the [Docker Swarm tutorial](https://docs.docker.com/engine/swarm/swarm-tutorial/create-swarm/).

```bash
$ docker swarm init --advertise-addr <ip_addess>
```

`<ip_address>` is required, even if we don't plan on attaching other nodes at this stage. It should be set to an IP on your private or internal network, not the public IP your server is accessible on.

### Install Postgres
Check the [postgres download page](https://www.postgresql.org/download/linux/ubuntu/) for the latest installation instructions. Included below are the instructions for postgres 12, the latest version as of the time of writing.

Create the repository configuration:

```bash
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
```

Import the repository signing key:

```bash
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
```

Refresh the local package index, then install postgres and utilities:

```bash
$ sudo apt update
$ sudo apt install postgresql postgresql-contrib
```

By default, postgres only allows connections over localhost. To access it from within docker containers, it must also listen for connections on the Docker bridge. In swarm mode, Docker creates a bridge network called `docker_gwbridge`, usually on `172.18.0.0/16`. You can inspect the network with `docker network inspect docker_gwbridge` to confirm.

Postgres' configuration file is at `/etc/postgresql/<version>/main/postgresql.conf`, where `<version>` is the postgres version you installed (12 is the latest at the time of writing). Look for the line containing `listen_address`, which by default will be commented out:

```bash
$ grep -n listen_address postgresql.conf 
59:#listen_addresses = 'localhost'              # what IP address(es) to listen on;
```

Open up the file in your editor of choice, uncomment the line, and add `172.18.0.1` to the list:

```
listen_addresses = 'localhost,172.18.0.1'
```

This host also needs to be added to the client authentication configuration file in `/etc/postgresql/<version>/main/pg_hba.conf`. Add the following under `# IPv4 local connections`:

```
host    all             all             172.18.0.1/16           md5
```

The second column is the database and the third is the user, you may change them if desired.

Restart postgres for the changes to take effect:

```bash
$ sudo service postgresql restart
```


Postgres, by default, requires you to be the `postgres` user/role in order to connect. Switch into the `postgres` user:

```bash
$ sudo su - postgres
```

Create a new database. We will call it `djangodb`:

```bash
$ createdb djangodb
```

Create a user that django will use to connect to the database. Let's call it `djangouser`. The user does not need to be a superuser, or able to create databases and roles.

```bash
$ createuser -P --interactive
Enter name of role to add: djangouser
Enter password for new role: 
Enter it again: 
Shall the new role be a superuser? (y/n) n
Shall the new role be allowed to create databases? (y/n) n
Shall the new role be allowed to create more new roles? (y/n) n
```

You can now `exit` out of the postgres user and return to whatever user account you began in.

```bash
$ exit
``` 

To confirm that the database and user were created correctly, launch a psql shell:

```bash
$ psql -d djangodb -h 127.0.0.1 -U djangouser
```

### Install Nginx
Nginx will run on the host, and will handle static file serving and as a reverse proxy to the swarm cluster. Install nginx:

```bash
$ sudo apt install nginx
```

At this point, it is helpful, but not required, to have a domain. This example uses `django-swarm-example.grahamhoyes.com`, which you may substitute for your own domain. SSL is not covered in this tutorial, but should be used in production. If not using SSL, you may substitute the domain name below with the public IP address of your server. Whichever approach you go, make sure to included it in `ALLOWED_HOSTS` of the [Django settings file](/app/app/settings/__init__.py).

Create a config file in `/etc/nginx/sites-available/`, for example `/etc/nginx/sites-available/django-swarm-example.conf`, with the following contents. If you aren't trying to deploy django under `/mysite`, you can replace it with just `/` in the config below.

```
upstream django_server {
    server localhost:8000;
}

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    server_name _;
    
    location /mysite {
        proxy_pass http://django_server;
        proxy_redirect off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $host;
        proxy_set_header X-Script-Name /mysite;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /mysite/static {
        alias /usr/src/grahamhoyes/django-docker-swarm-example/static/;
    }
}
```

Disable the default nginx site, and enable the one you just created by creating a symlink:

```bash
$ sudo rm /etc/nginx/sites-enabled/default
$ sudo ln -s /etc/nginx/sites-available/django-swarm-example.conf /etc/nginx/sites-enabled/django-swarm-example.conf
```

Reload nginx for the changes to take effect:

```bash
$ sudo systemctl reload nginx
```

### SSH Keys
Since we do not expose the Docker API, deploying happens by transferring compose files to the server over SCP, and running the deploy command over SSH. We'll need on SSH key to do that, so on the server run:

```bash
$ ssh-keygen -t rsa -b 4096 -C "you@example.com"
```

If you want to save the file somewhere other that `~/.ssh/id_rsa.pub` you may do so, and update the commands below accordingly.

Add the public key to the server's authorized keys:

```bash
$ cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
```

Make note of which user's `authorized_keys` file you added the public key to (i.e. who you were logged in as), as this will be the user that deployment happens through. The user will need to have appropriate docker permissions. Set this user in the `SSH_USER` GitHub secret (see below).

Copy the full contents of the SSH public key into the `SSH_PRIVATE_KEY` secret key on GitHub (see below). Copy the entire key, including the begin and end messages.

## Secrets
Sensitive credentials, such as the database username and password, are stored in GitHub repository secrets. See [Creating and storing encrypted secrets](https://docs.github.com/en/actions/configuring-and-managing-workflows/creating-and-storing-encrypted-secrets) for more information on how to setup secrets.

Setup the following secrets:

| **Secret name** | **Description** |
| --- | --- |
| `SECRET_KEY` | The Django [secret key](https://docs.djangoproject.com/en/2.2/ref/settings/#std:setting-SECRET_KEY) |
| `DB_NAME` | Database name. `djangodb` in this example. |
| `DB_USER` | Database user. `djangouser` in this example. |
| `DB_PASSWORD` | Database password, set during user creation. |
| `DB_HOST` | Database host. If postgres is running natively on the same server as the single Swarm node, this should be `172.18.0.1`. |
| `DB_PORT` | Database port. For postgres, the default is `5432`. |
| `SWARM_MANAGER_IP` | Public IP of the Swarm manager node that we can ssh to. Note that this is not the same as the IP address provided to `--advertise-addr` when initializing the swarm. |
| `SSH_USER` | User to SSH over and deploy as. |
| `SSH_PRIVATE_KEY` | SSH private key, generated above. Must correspond to the `SSH_USER`. |

## The workflow
The GitHub workflow that runs checks, builds, and deploys is in [.github/workflows/main.yml](.github/workflows/main.yml).