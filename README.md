# Django Docker Swarm Example
An example project for deploying Django on Docker Swarm.

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

By default, postgres only allows connections over localhost. To access it from within docker containers, it must also listen for connections on the Docker bridge. Usually this is on `172.17.0.1`, you can run `ip a` to confirm. 

Postgres' configuration file is at `/etc/postgresql/<version>/main/postgresql.conf`, where `<version>` is the postgres version you installed (12 is the latest at the time of writing). Look for the line containing `listen_address`, which by default will be commented out:

```bash
$ grep -n listen_address postgresql.conf 
59:#listen_addresses = 'localhost'              # what IP address(es) to listen on;
```

Open up the file in your editor of choice, uncomment the line, and add `172.17.0.1` to the list:

```
listen_addresses = 'localhost,172.17.0.1'
```

Reload postgres fro the changes to take effect:

```bash
$ sudo systemctl reload postgresql
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
| `DB_PASSWORD` | Database password, set during user creation |
| `DB_HOST` | Database host. If postgres is running natively on the same server as the single Swarm node, this should be `172.17.0.1`. |
| `DB_PORT` | Database port. For postgres, the default is `5432`. |
| `SWARM_MANAGER_IP` | Public IP of the Swarm manager node that we can ssh to. Note that this is not the same as the IP address provided to `--advertise-addr` when initializing the swarm.
| `SSH_USER` | User to SSH over and deploy as |
| `SSH_PRIVATE_KEY` | SSH private key, generated above. Must correspond to the `SSH_USER`. |

