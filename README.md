# Django Docker Swarm Example
An example project for deploying Django on Docker Swarm.

This is primarily a playground and documentation for [IEEE UofT's](https://ieee.utoronto.ca/) deployment needs to serve our [hackathon template](https://github.com/ieeeuoft/hackathon-template). As such, the requirements are:
- Runs on a single server, but the option to add more nodes in the future is preferred
- Postgres is installed natively on the server
- Nginx is installed natively on the server, handling SSL and static file serving. We were using Apache, but after trying to get the reverse proxy for this tutorial to work properly we gave up and switched to Nginx. Would recommend.
- The application should be deployed as a docker container that Apache/Nginx can reverse proxy to
- Multiple independent instances must be possible (for multiple events)
- Applications must be able to run under a sub-folder of the website, i.e. ieee.utoronto.ca/event1, ieee.utoronto.ca/event2

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

`<ip_address>` is required, even if we don't plan on attaching other nodes at this stage. It should be set to an IP on your private or internal network, not the public IP your server is accessible on. If your server only has a public IP, make sure to block whatever port the swarm advertises on (will be printed after initialized) on your server's firewall.

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

By default, postgres only allows connections over localhost. To access it from within docker containers, it must also listen for connections on the Docker bridge. In swarm mode, Docker creates a bridge network called `docker_gwbridge`, usually on `172.18.0.0/16`, but this may change. You should inspect the network with `docker network inspect docker_gwbridge` to confirm.

Postgres' configuration file is at `/etc/postgresql/<version>/main/postgresql.conf`, where `<version>` is the postgres version you installed (12 is the latest at the time of writing). Look for the line containing `listen_address`, which by default will be commented out:

```bash
$ grep -n listen_address postgresql.conf 
59:#listen_addresses = 'localhost'              # what IP address(es) to listen on;
```

Open up the file in your editor of choice, uncomment the line, and add `172.18.0.1` (or the address of your `docker_gwbridge`) to the list:

```
listen_addresses = 'localhost,172.18.0.1'
```

This host also needs to be added to the client authentication configuration file in `/etc/postgresql/<version>/main/pg_hba.conf`. Add the following under `# IPv4 local connections` (again, changing the address to that of `docker_gwbridge` if necessary):

```
host    all             all             172.18.0.1/16           md5
```

The second column is the database and the third is the user, you may change them to `djangodb` and `djangouser` if you would like to limit the user's connection to just the newly created database.

Restart postgres for the changes to take effect:

```bash
$ sudo service postgresql restart
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

Create a config file in `/etc/nginx/sites-available/`, for example `/etc/nginx/sites-available/django-swarm-example.conf`, with the following contents. If you aren't trying to deploy django under `/mysite`, you can replace it with just `/` in the config below. Static files are placed in `/usr/src/<username>/<repository>/static/` by default, which you can customize in the [workflow](#deploy).

```
upstream django_server {
    server localhost:8000;
}

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    server_name django-swarm-example.grahamhoyes.com;
    
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
| `DB_HOST` | Database host. If postgres is running natively on the same server as the single Swarm node, this should be `172.18.0.1`, or the address of `docker_gwbridge`. |
| `DB_PORT` | Database port. For postgres, the default is `5432`. |
| `SWARM_MANAGER_IP` | Public IP of the Swarm manager node that we can ssh to. Note that this is not the same as the IP address provided to `--advertise-addr` when initializing the swarm. |
| `SSH_USER` | User to SSH over and deploy as. |
| `SSH_PRIVATE_KEY` | SSH private key, generated above. Must correspond to the `SSH_USER`. |

## The workflow
The GitHub workflow that runs checks, builds, and deploys is in [.github/workflows/main.yml](.github/workflows/main.yml). Let's go over it.

### Basic config
The beginning of the file defines the name of the workflow. Afterwards, the workflow is set to be triggered on push to any branch in the repo. Later on, we will limit the build and deploy stages to only run on master.

Top-level settings are specified in the `env` section. `IMAGE_ROOT` will be the prefix for the image tag when the services are built. `${{ github.repository }}` is `<username>/<repository>`. For this example, `IMAGE_ROOT` will become `docker.pkg.github.com/grahamhoyes/django-docker-swarm-experiment`.

```yaml
name: CI/CD

on:
  push:
    branches: '**'

env:
  IMAGE_ROOT: docker.pkg.github.com/${{ github.repository }}
  STACK_NAME: django-swarm-example
```

### Jobs
#### Checks
The file proceeds by defining a series of jobs. The first of these is for checks, which starts by checking out the repo (all jobs will begin with this), installing python and dependencies, linting with `black`, and finally running django tests. In order to run tests, the `SECRET_KEY` environment must be set. We do so, pulling it from the secrets defined above.

```yaml
jobs:
  checks:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: app

    steps:
      - uses: actions/checkout@v2
      - name: Set up Python 3.8
        uses: actions/setup-python@v1
        with:
          python-version: 3.8
      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
      - name: Lint
        run: black --check .
      - name: Tests
        env:
          SECRET_KEY: ${{ secrets.SECRET_KEY }}
        run: python manage.py test --settings=app.settings.ci
```

#### Build
Next, we build and push the docker container. By specifying `needs: [checks]`, we ensure that the checks job has completed before this job is run. This job will also only run on the master branch. The working directory is set to `app`, so step will execute within that directory by default.

Each docker image will be tagged with the shortened git commit sha, to prevent ambiguities around using `:latest`. The short sha is just the first 7 characters of the long sha, and could also be obtained by `git rev-parse --short <commit sha>`. This is set as an environment variable, as it is used by [deployment/docker-compose.ci.yml](deployment/docker-compose.ci.yml) to tag the image, along with `$IMAGE_ROOT`. It is also set as an output of the job, so that it can be used in the deploy job.

Once the image is built, it is pushed to GitHub packages. In order to do so, we must first log in to the docker client. `secrets.GITHUB_TOKEN` is automatically set by the GitHub actions runner to be a unique access token, with permissions only for the current repository. `github.actor` will be the user who triggers the pipeline. Once logged in, the image can be pushed and will appear in the [packages of the repo](https://github.com/grahamhoyes/django-docker-swarm-example/packages).

```yaml
  build:
    runs-on: ubuntu-latest
    needs: [checks]
    if: github.ref == 'refs/heads/master'
    outputs:
      GITHUB_SHA_SHORT: ${{ steps.sha7.outputs.GITHUB_SHA_SHORT }}

    steps:
      - uses: actions/checkout@v2
      - name: Get short SHA
        id: sha7
        run: |
          echo "::set-env name=GITHUB_SHA_SHORT::$(echo ${{ github.sha }} | cut -c1-7)"
          echo "::set-output name=GITHUB_SHA_SHORT::$(echo ${{ github.sha }} | cut -c1-7)"
      - name: Build image
        run: docker-compose -f deployment/docker-compose.ci.yml build
      - name: Authenticate Docker with GitHub Packages
        run: |
          echo ${{ secrets.GITHUB_TOKEN }} | docker login https://docker.pkg.github.com -u ${{ github.actor }} --password-stdin
      - name: Push image
        run: docker-compose -f deployment/docker-compose.ci.yml push
```

#### Deploy
This is the most complex stage of the workflow. It requires that both the checks and build jobs have completed (listing checks is redundant, since build requires it already). The job will also only be run on master. The working directory is set to `deployment`, so every step (except the SCP step, more below) will execute there by default.

```yaml
  deploy:
    runs-on: ubuntu-latest
    needs: [checks, build]
    if: github.ref == 'refs/heads/master'
    defaults:
      run:
        working-directory: deployment
```

We start by installing python and dependencies again (workspaces aren't preserved between jobs, so we can't reuse the state from the checks job). Then we run `python manage.py collectstatic`, to collect django's static files into a single directory. This also requires a secret key.

```yaml
    steps:
      - uses: actions/checkout@v2
      - name: Set up Python 3.8
        uses: actions/setup-python@v1
        with:
          python-version: 3.8
      - name: Install dependencies
        working-directory: app
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
      - name: Collect static
        working-directory: app
        env:
          SECRET_KEY: ${{ secrets.SECRET_KEY }}
        run: python manage.py collectstatic
```

Next, we set all of the necessary environment variables for the deployment in a `.env` file, which is used by [deployment/docker-compose.prod.yml](deployment/docker-compose.prod.yml). We then do some string substitution with `sed` on the latter file to build the full image tag from `$IMAGE_ROOT` and `$GITHUB_SHA_SHORT`, the later of which is taken from the output of the `build` stage (which we have access to because `build` is in this job's `needs` list). Alternatively, we could have left these as environment variables and set those environment variables on the host while deploying.

```yaml
      - name: Set environment variables in .env
        run: |
          echo 'DEBUG=0' >> .env
          echo 'SECRET_KEY=${{ secrets.SECRET_KEY }}' >> .env
          echo 'DB_NAME=${{ secrets.DB_NAME }}' >> .env
          echo 'DB_USER=${{ secrets.DB_USER }}' >> .env
          echo 'DB_PASSWORD=${{ secrets.DB_PASSWORD }}' >> .env
          echo 'DB_HOST=${{ secrets.DB_HOST }}' >> .env
          echo 'DB_PORT=${{ secrets.DB_PORT }}' >> .env
      - name: Substitute variables in compose file
        run: |
          cp docker-compose.prod.yml docker-compose.prod.tmp.yml
          cat docker-compose.prod.tmp.yml \
            | sed "s,{{IMAGE_ROOT}},${{ env.IMAGE_ROOT }},g" \
            | sed "s,{{GITHUB_SHA_SHORT}},${{ needs.build.outputs.GITHUB_SHA_SHORT }},g" \
            > docker-compose.prod.yml
```

The deployment and static files are then transferred to the server over scp using [scp-action](https://github.com/appleboy/scp-action). This action doesn't obey the `working-directory` of the job, so we have to use absolute paths.

Files on the server are sent to `/usr/src/<username>/<repository>/`, so make sure the user you are using for SCP/SSH has the necessary permissions. If you change this, make sure to change the nginx config above as well. `strip_component: 1` removes the first folder in the file path, which in our case strips `deployment/` out when sending the files to the server.

```yaml
      - name: Transfer deployment and static files to the Swarm manager
        uses: appleboy/scp-action@v0.1.1
        with:
          host: ${{ secrets.SWARM_MANAGER_IP }}
          username: ${{ secrets.SSH_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          overwrite: true
          # scp-action doesn't obey working-directory, runs at repo root
          source: "deployment/.env,deployment/docker-compose.prod.yml,app/static/"
          target: "/usr/src/${{ github.repository }}"
          strip_components: 1
```

Finally, the deployment is brought up over SSH.

Once again, we must log in to docker to pull the image. `--with-registry-auth` is required in the `docker-stack-deploy` command to pass these credentials through to other nodes in the swarm, if there are any.

We use [docker-stack-wait](https://github.com/sudo-bmitch/docker-stack-wait) to pause until the deployment is complete. Afterwards, we get the ID of a container on the node that we can run migrations in. This will fail if you have multiple nodes, and it so happens that none of the service replicas end up on the manager. In this case, you can either find the node and switch `DOCKER_HOST` there, or try using `docker run` or `docker-compose run`, but these require some extra configuration to postgres since the run outside of the `docker_gwbridge` network.

After that, we remove the files with sensitive information (`docker logout` will delete it's saved credentials), and we're done!

```yaml
      - name: Bring up deployment
        uses: appleboy/ssh-action@v0.1.3
        with:
          host: ${{ secrets.SWARM_MANAGER_IP }}
          username: ${{ secrets.SSH_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          script_stop: true
          script: |
            cd /usr/src/${{ github.repository }}
            docker pull sudobmitch/docker-stack-wait
            echo ${{ secrets.GITHUB_TOKEN }} | docker login docker.pkg.github.com -u ${{ github.actor }} --password-stdin
            docker stack deploy --with-registry-auth -c docker-compose.prod.yml ${{ env.STACK_NAME }}

            # Wait for deployment to complete
            docker run --rm \
              -v /var/run/docker.sock:/var/run/docker.sock \
              sudobmitch/docker-stack-wait ${{ env.STACK_NAME }}

            # Run migrations
            # TODO: This will fail if at least one replica isn't running on the node, will need to
            # switch DOCKER_HOST over ssh
            service_id=$(docker ps -f "name=${{ env.STACK_NAME }}_django" -q | head -n1)
            docker exec $service_id python manage.py migrate

            # Cleanup
            rm .env
            docker logout docker.pkg.github.com
```