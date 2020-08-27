# Django Docker Swarm Example
An example project for deploying Django on Docker Swarm.

This project walks through installing a postgres server, docker engine, and initializing Docker Swarm on a single machine (i.e., we will be creating a Swarm cluster with a single node). 

This project does not:
- Use [Docker Machine](https://docs.docker.com/machine/), because my use case is running on an existing server.
- Expose the Docker API. All remote connections will be made over SSH.

## Credits
The following resources were a great help in developing this example:
- https://github.com/testdrivenio/django-github-digitalocean


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

SSH into the machine, and follow the steps below.

### Install Postgres
Refresh the local package index, then install postgres and utilities:

```bash
$ sudo apt update
$ sudo apt install postgresql postgresql-contrib
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

### Install Docker
Install Docker Engine by following the steps in the [Docker documentation](https://docs.docker.com/engine/install/ubuntu/).

### Create the Swarm
In this example, we will be working on a single-node swarm. For a full example of how to create a swarm and attach worker nodes, follow the [Docker Swarm tutorial](https://docs.docker.com/engine/swarm/swarm-tutorial/create-swarm/).

```bash
$ docker swarm init --advertise-addr <ip_addess>
```

`<ip_address>` is required, even if we don't plan on attaching other nodes at this stage. It should be set to an IP on your private or internal network, not the public IP your server is accessible on.

## Secrets
Sensitive credentials, such as the database username and password, are stored in GitHub repository secrets. See [Creating and storing encrypted secrets](https://docs.github.com/en/actions/configuring-and-managing-workflows/creating-and-storing-encrypted-secrets) for more information on how to setup secrets.

Setup the following secrets:

| **Secret name** | **Description** |
| --- | --- |
| `SECRET_KEY` | The Django [secret key](https://docs.djangoproject.com/en/2.2/ref/settings/#std:setting-SECRET_KEY) |
| `DB_NAME` | Database name. `djangodb` in this example. |
| `DB_USER` | Database user. `djangouser` in this example. |
| `DB_PASSWORD` | Database password, set during user creation |
| `DB_HOST` | Database host. If postgres is running natively on the same server as the single Swarm node, this should be `127.0.0.1`. |
| `DB_PORT` | Database port. For postgres, the default is `5432`. |

