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
        # chmod -R 0600 /home/yourname/.ssh/*

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

The swarm deployment can run as any user with SSH and docker privileges. If you would like to run the deployment as whatever user you SSHd in with, you can skip this step. Otherwise, create a new user (which we will call ``deploy``) and add them to the ``docker`` group:

.. code-block:: console

    $ sudo adduser deploy
    $ sudo usermod -aG docker deploy

Install and Configure Postgres
------------------------------

Check the `postgres download page <https://www.postgresql.org/download/linux/ubuntu/>`_ for the latest installation instructions. At the time of writing, Postgresql 13 is the latest release. Follow the steps to add the repository, import the repository signing key, and update package lists.

When it comes time to install postgres, also install the ``postgresql-contrib`` package:

.. code-block:: console

    $ sudo apt install postgresql postgresql-contrib

You can verify the install succeeded by running ``sudo service postgresql status``, or ``pg_isready``.

Create the Database
+++++++++++++++++++

By default, postgres requires you to be teh ``postgres`` user/role in order to connect. Switch into the ``postgres`` user:

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

Configure Connection Rules
++++++++++++++++++++++++++

By default, postgres only allows connections over localhost. To access it from within docker containers, it must also listen for connections on the Docker bridge network. In swarm mode, docker creates a bridge network called ``docker_gwbridge``, usually on ``172.18.0.0/16``, but this may change.

Inspect the network to confirm the gateway address:

.. code-block:: console

    $ docker network inspect docker_gwbridge --format="{{range .IPAM.Config}}{{.Gateway}}{{end}}"
    172.18.0.1

Postgres' configuration file is at ``/etc/postgresql/<version>/main/postgresql.conf``, where ``<version>`` is the version you installed (13 at the time of writing). Look for the line containing ``listen_address``, which by default will be commented out:

.. code-block:: console

    $ cd /etc/postgresql/13/main/
    $ grep -n listen_address postgresql.conf
    59:#listen_addresses = 'localhost'              # what IP address(es) to listen on;

Open up the file in your editor of choice (with ``sudo``), uncomment the line, and add ``127.18.0.1`` (or the gateway address of your ``docker_gwbridge``) ot the list::

    listen_addresses = 'localhost,172.18.0.1'

This host also needs to be added to the client authentication configuration file in ``/etc/postgresql/<version>/main/pg_hba.conf``. Add the following under ``# IPv4 local connections`` (changing the address to that of ``docker_gwbridge`` if necessary)::

    host    djangodb        djangouser      172.18.0.1/16           md5

The second column is the database and the third is the user, you can change them to ``all`` if you don't want to limit connections to only the newly created user and database.

Restart postgres for the changes to take effect:

.. code-block:: console

    $ sudo service postgresql restart

To confirm that the database and user were created correctly, launch a psql shell (typing ``\q`` to quit):

.. code-block:: console

    $ psql -d djangodb -h 127.0.0.1 -U djangouser

Install and Configure Nginx
---------------------------