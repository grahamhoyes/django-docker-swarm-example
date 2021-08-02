Server Setup
============

In this section, we will cover deploying to a single-node Swarm cluster. The node will also run Postgres and Nginx natively (outside of Docker). Both of these could also be hosted externally, with appropriate network security measures taken.

Create a server using your cloud provider of choice. For this example, I am using a Digital Ocean droplet running Ubuntu 20.04 with 1 GB of RAM and 1 vCPU. Provision the server to use SSH keys, and have a non-root user with sudo privileges to work in.

.. note::
    Digital Ocean only creates a root user at droplet setup, whether using SSH keys or not. To add a non-root user, perform the following (substituting ``yourname`` for your username of choice):

    .. code-block:: console

        $ ssh -y root@<server IP>
        # adduser yourname
        # usermod -aG sudo yourname
        # cp -r /root/.ssh /home/yourname
        # chown -R yourname:yourname /home/yourname/.ssh
        # chmod -R 600 /home/yourname/.ssh/*

    Log out, then log back in using ``ssh yourname@<server IP>``.

SSH into the machine, and follow the steps below.

Setup Docker and Swarm Mode
---------------------------
Install Docker Engine by following the steps in the `Docker documentation <https://docs.docker.com/engine/install/ubuntu/>`_.

Once installed, add yourself to the docker group:

.. code-block:: console

    $ sudo usermod -aG docker $USER

In order for the group change to take effect, log out and log back in.

Create the Swarm
++++++++++++++++
In this section, we will be working on a single-node swarm. For a full example of how to create a swarm and attach worker nodes, follow the `Docker Swarm tutorial <https://docs.docker.com/engine/swarm/swarm-tutorial/create-swarm/>`_.

.. code-block:: console

    $ docker swarm init --advertise-addr <ip address>

``<ip address>`` is required, even if we don't plan on attaching any other nodes at this stage. It should be set to an IP on your VPC or internal network, not the public IP your server is accessible on. If your server only has a public IP, make sure to block whatever port the swarm advertises on (will be printed after initialization) on your server's firewall.

Optional: Create a Deployment User
++++++++++++++++++++++++++++++++++

The swarm deployment can run as any user with SSH and docker privileges. If you would like to run the deployment as whatever user you SSHd in with, you can skip this step. Otherwise, create a new user (which we will call ``deployer``) and add them to the ``docker`` group:

.. code-block:: console

    $ sudo adduser deployer
    $ sudo usermod -aG docker deployer

.. note::

    To prevent a possible avenue for brute-force attacks, you should give your deploy user a non-generic name (something better than ``deployer``, which we use here for simplicity).

Folder Setup
------------

There are two persistent folders required for deployment: a folder for static files, and a folder for user-uploaded media files.

The workflow is configured to send static files to ``/usr/src/<username>/<repository>/static/``, which is served by nginx (see the :ref:`nginx config <nginx-config>`). We need to create the repository folder, and assign permissions to the user the deploy will be running as. Replace ``<username>/<repository>`` below with your username and repository, for example ``grahamhoyes/django-docker-swarm-example``:

.. code-block:: console

    $ sudo mkdir -p /usr/src/<username>/<repository>
    $ sudo chown -R deployer:deployer /usr/src/<username>/<repository>
    $ sudo chmod -R 755 /usr/src/<username>/<repository>

User-uploaded media files are configured to go to ``/var/www/<username>/<repository>/media/``, via the volume mount in `deployment/docker-compose.prod.yml <https://github.com/grahamhoyes/django-docker-swarm-example/blob/master/deployment/docker-compose.prod.yml>`_. Create and set permissions on that folder as well, substituting your username, repository, and deploy user:

.. code-block:: console

    $ sudo mkdir -p /var/www/<username>/<repository>/media
    $ sudo chown -R deployer:deployer /var/www/<username>/<repository>/media
    $ sudo chmod -R 751 /var/www/<username>/<repository>/media

.. note::
    When the django container runs, it will run as the ``root`` user internally. When it writes media files via the volume mount, they will be owned by ``root:root`` as a result. The ``751`` permissions octal above will give the ``deployer`` user rwx permissions, the ``deployer`` group rx permissions, and other users only execute permissions. If you would like media files to be accessible manually outside of django, there are two options:

    * Change the final byte of the permissions octal to something that allows reading from any user, like ``755``
    * Change the user that the django container runs as to match your deploy user. This involves finding the user and group IDs of your deploy user, creating a :ref:`GitHub secret <secrets>` for  them, and passing them in to ``docker-compose.prod.yml`` via the ``user`` key. See this `Stack Overflow post <https://stackoverflow.com/a/56904335>`_ for more information.

Install and Configure Postgres
------------------------------

Check the `postgres download page <https://www.postgresql.org/download/linux/ubuntu/>`_ for the latest installation instructions. At the time of writing, Postgresql 13 is the latest release. Follow the steps to add the repository, import the repository signing key, and update package lists.

When it comes time to install postgres, also install the ``postgresql-contrib`` package:

.. code-block:: console

    $ sudo apt install postgresql postgresql-contrib

You can verify the install succeeded by running ``sudo service postgresql status``, or ``pg_isready``.

Create the Database
+++++++++++++++++++

By default, postgres requires you to be the ``postgres`` user/role in order to connect. Switch into the ``postgres`` user:

.. code-block:: console

    $ sudo su - postgres

Create a new database. We will call it ``djangodb``:

.. code-block:: console

    $ createdb djangodb

Create a user that django will use to connect to the database. Let's call it ``djangouser``. The user does not need to be a superuser, or able to create databases and roles.

.. code-block:: console

    $ createdb djangodb
    $ createuser -P --interactive
    Enter name of role to add: djangouser
    Enter password for new role:
    Enter it again:
    Shall the new role be a superuser? (y/n) n
    Shall the new role be allowed to create databases? (y/n) n
    Shall the new role be allowed to create more new roles? (y/n) n

You can now ``exit`` out of the postgres user and return to whatever user account you began in.

.. code-block:: console

    $ exit

.. _configure-connection-rules:

Configure Connection Rules
++++++++++++++++++++++++++

By default, postgres only allows connections over localhost. To access it from within docker containers, it must also listen for connections on the Docker bridge network. In swarm mode, docker creates a bridge network called ``docker_gwbridge``, usually on ``172.18.0.0/16``, but this may change.

Inspect the network to confirm the gateway address:

.. code-block:: console

    $ docker network inspect docker_gwbridge --format="{{range .IPAM.Config}}{{.Gateway}}{{end}}"
    172.18.0.1

In addition, we will also need the address of the regular ``bridge`` network, which is used to run migrations (the container running migrations is not part of the swarm deployment). This is usually on ``172.17.0.0/16``, but confirm this as well:

.. code-block:: console

    $ docker network inspect bridge

.. note::

    The bridge network may not always report a gateway. If you see, for example, ``172.17.0.0/16`` listed as the subnet, you can use ``172.17.0.1`` as the gateway address below.

Postgres' configuration file is at ``/etc/postgresql/<version>/main/postgresql.conf``, where ``<version>`` is the version you installed (13 at the time of writing). Look for the line containing ``listen_address``, which by default will be commented out:

.. code-block:: console

    $ cd /etc/postgresql/13/main/
    $ grep -n listen_address postgresql.conf
    59:#listen_addresses = 'localhost'              # what IP address(es) to listen on;

Open up the file in your editor of choice (with ``sudo``), uncomment the line, and add ``127.18.0.1`` (or the gateway address of your ``docker_gwbridge``) ot the list::

    listen_addresses = 'localhost,172.18.0.1'

This host also needs to be added to the client authentication configuration file in ``/etc/postgresql/<version>/main/pg_hba.conf``. Add the following under ``# IPv4 local connections`` (changing the addresses to those of ``docker_gwbridge`` and ``bridge`` if necessary)::

    host    djangodb        djangouser      172.18.0.1/16           md5
    host    djangodb        djangouser      172.17.0.1/16           md5

The second column is the database and the third is the user, you can change them to ``all`` if you don't want to limit connections to only the newly created user and database.

Restart postgres for the changes to take effect:

.. code-block:: console

    $ sudo service postgresql restart

To confirm that the database and user were created correctly, launch a psql shell (typing ``\q`` to quit):

.. code-block:: console

    $ psql -d djangodb -h 127.0.0.1 -U djangouser

.. _nginx-config:

Install and Configure Nginx
---------------------------

Nginx will run on the host, and will handle static file service, SSL, and act as a reverse proxy to the swarm cluster. Install nginx:

.. code-block:: console

    $ sudo apt install nginx

At this point, it is helpful, but not required, to have a domain. This example uses ``django-swarm-example.grahamhoyes.com``, which you may substitute for your own domain. SSL should be used in production, which if using letsencrypt for free certificates, requires a domain. If not using SSL, you may substitute the domain name below with the public IP address of your server. Whichever approach you choose, make sure to include it in ``ALLOWED_HOSTS`` of the main django settings file.

Create a new config file in ``/etc/nginx/sites-available/``, for example ``/etc/nginx/sites-available/django-swarm-example.conf``, with the following contents (substituting in your domain and repository path). Static files are placed in ``/usr/src/<username>/<repository>/static`` by default, which you can customize in the `workflow <https://github.com/grahamhoyes/django-docker-swarm-example/#deploy>`_.

.. code-block:: text

    upstream django_server {
        server localhost:8000;
    }

    server {
        listen 80 default_server;
        listen [::]:80 default_server;

        server_name django-swarm-example.grahamhoyes.com;

        location / {
            proxy_pass http://django_server;
            proxy_redirect off;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $host;
            proxy_set_header X-Script-Name '';
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /static {
            # Replace this path with /usr/src/<your username>/<repository>/static
            alias /usr/src/grahamhoyes/django-docker-swarm-example/static/;
        }
    }

The `production docker-compose file <https://github.com/grahamhoyes/django-docker-swarm-example/blob/master/deployment/docker-compose.prod.yml>`_ that defines the swarm stack runs django on port 8000 (using gunicorn, not the development server), hence the port within the upstream block. This can be easily changed.

Disable the default nginx site, and enable the one you just created by creating a symlink:

.. code-block:: console

    $ sudo rm /etc/nginx/sites-enabled/default
    $ sudo ln -s /etc/nginx/sites-available/django-swarm-example.conf /etc/nginx/sites-enabled/django-swarm-example.conf

Reload nginx for the changes to take effect:

.. code-block:: console

    $ sudo service nginx reload

Optional (not really): SSL from Let's Encrypt
+++++++++++++++++++++++++++++++++++++++++++++

`Certbot <https://certbot.eff.org/>`_ is a tool for automating obtaining and renewing SSL certificates from Let's Encrypt. Let's Encrypt requires that you have a domain, so if you did not include a domain name in the nginx configuration file, then skip this step.

Follow the instructions `here <https://certbot.eff.org/lets-encrypt/ubuntufocal-nginx>`_ to install certbot for Ubuntu 20.04 and Nginx (or your choice of OS and web server).

Once you've installed certbot and have the ``certbot`` command setup, we can let certbot do all the heavy lifting for us to set up SSL for our newly configured nginx site:

.. code-block:: console

    $ sudo certbot --nginx

Enter an email address for renewal and security notices, and accept the Terms of Service. When asked which names you would like to activate HTTPS for, enter the number of the site you just added (which will probably be 1). Certbot will obtain an SSL certificate, and will automatically manage renewing it.

If you now open the nginx config file (``/etc/nginx/sites-available/django-swarm-example.conf``), you will notice a few lines have been added by certbot to tie in the SSL certificates, and redirect all HTTP traffic to HTTPS. You can continue making changes to this file as necessary. If you need to disable HTTPS in the future, remove all the lines added by certbot.

If you visit your domain now, you should be met with a "502 Bad Gateway" page, but the connection should be over HTTPS.

Optional: Serving Media Files
+++++++++++++++++++++++++++++

Media files (user-uploaded content) are placed under ``/var/www/<username>/<repository>/media`` by default. There is no logic in the django app to actually serve these right now, but typically you would want to create a view that will authenticate a user before allowing them access to media files. Sending files back through django is not great for performance, `here's an article <https://docs.djangoproject.com/en/3.1/howto/deployment/wsgi/apache-auth/>`_ on how to integrate django authentication with Apache (I will update this tutorial when I have figured out how for nginx).

For now, we can configure nginx to serve media files by adding the following location block:

.. code-block:: text

    location /media {
        # Replace this path with /var/www/<your username>/<repository>/media
        alias /var/www/grahamhoyes/django-docker-swarm-example/media/;
    }

Reload nginx for the changes to take effect:

.. code-block:: console

    $ sudo service nginx reload

.. _ssh-keys:

SSH Keys
--------

Since we do not want to expose the Docker API, deploying happens by pointing the docker CLI running in GitHub Actions to a remote docker engine (running on our server) over SSH. SSH is also used to transfer over static files. We'll need an SSH key to do that.

If you're using a separate ``deployer`` user, switch to that user now:

.. code-block:: console

    $ sudo su - deployer

Generate an ssh key, filling in your email address:

.. code-block:: console

    $ ssh-keygen -t rsa -b 4096 -C "you@example.com"

If you want to save the file somewhere other than ``~/.ssh/id_rsa`` you may do so, and update the commands below accordingly. Do not set a passphrase, as this key will be used by the automated GitHub Actions runner.

Add the public key to the user's authorized keys, and give the file the correct permissions:

.. code-block:: console

    $ cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
    $ chmod 600 ~/.ssh/authorized_keys

Make note of which user's ``authorized_keys`` file you added the public key to (i.e., which user you logged in as or switched to), as this will be the user that deployment happens through. The user will need to have appropriate docker permissions, which if this guide was followed properly, they should have.

In the next section, we will set this user in the ``SSH_USER`` GitHub secret. The entire contents of the SSH private key (``cat ~/.ssh/id_rsa``) will be set in the ``SSH_PRIVATE_KEY`` secret.