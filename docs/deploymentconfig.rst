Deployment Configuration
========================

For this example, we use GitHub repository secrets to manage our deployment secrets, and GitHub Actions to run the deployment pipeline. You could substitute these for a CI runner of your choice (CircleCI, Jenkins, etc).

Secrets
-------
Sensitive credentials, such as the database username and password, are stored in GitHub repository secrets. See the `GitHub docs on secrets <https://docs.github.com/en/actions/reference/encrypted-secrets>`_ for more information on how to setup repository secrets.

Create the following repository secrets:

.. list-table::
    :widths: 1 3
    :header-rows: 1

    * - Secret name
      - Description
    * - ``SECRET_KEY``
      - The Django `secret key <https://docs.djangoproject.com/en/2.2/ref/settings/#std:setting-SECRET_KEY>`_. Generate something secure, and keep it a secret.
    * - ``CI_SECRET_KEY``
      - The Django secret key to be used in a CI environment, NOT for deployment. This is to keep your primary secret key from being passed to actions running from forks, if enabled.
    * - ``DB_NAME``
      - Database name. ``djangodb`` in this example.
    * - ``DB_USER``
      - Database user. ``djangouser`` in this example.
    * - ``DB_PASSWORD``
      - Database password, set during user creation.
    * - ``DB_HOST``
      - Database host. If postgres is running natively on the same server as the single Swarm node, this should be ``172.18.0.1``, or the address of ``docker_gwbridge``. This is what we entered when :ref:`configuring postgres connections <configure-connection-rules>`.
    * - ``DB_PORT``
      - Database port. For postgres, the default is 5432.
    * - ``REDIS_URI``
      - Redis URI. We can use ``redis:6379/app`` to resolve the ``redis`` service via DNS. ``app`` is the redis database name, and is arbitrary.
    * - ``SWARM_MANAGER_IP``
      - Public IP of the Swarm manager node that we can ssh to. Note that this is not necessarily the same as the IP address provided to ``--advertise-addr`` when initializing the swarm, if a private IP was used.
    * - ``SSH_USER``
      - User to SSH over and deploy as. This is the user used when :ref:`setting up SSH keys <ssh-keys>`.
    * - ``SSH_PRIVATE_KEY``
      - SSH private key, generated when :ref:`setting up SSH keys <ssh-keys>`. This must be the entire key (output of ``cat ~/.ssh/id_rsa`` when logged is a the ``SSH_USER``), including the begin and end messages.
