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

At this point, you should be able to trigger the workflow to run the deployment. To trigger the workflow, either make a commit and push to the ``master`` branch, or re-run the most recent job by opening your fork on GitHub, clicking the "Actions" tab, selecting the most recent workflow, and clicking "Re-run jobs".

.. |MainWorkflow| replace:: ``.github/workflows/main.yml``
.. _MainWorkflow: https://github.com/grahamhoyes/django-docker-swarm-example/blob/master/.github/workflows/main.yml

Below, we'll walk through the default workflow at |MainWorkflow|_.

The Workflow
------------

The GitHub workflow that runs checks, builds, and deploys is in |MainWorkflow|_. It is ready to run-as is, but can be customized as necessary. Let's walk through what's there.

Basic Config
++++++++++++

The beginning of the file defines the name of the workflow. Afterwards, the workflow is set to be triggered on push to any branch in the repo. Later on, we will limit the build and deploy stages to only run on pushes to the ``master`` branch.

Top-level settings are specified in the ``env`` section. ``REGISTRY`` sets the Docker container registry used for pushing images. ``ghcr.io`` is the `GitHub container registry <https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry>`_, which is free for public repositories. ``IMAGE_NAME`` is the name of the built image, which will be ``<username>/<repository>``. ``STACK_NAME`` is the name of the stack that will be deployed.

.. code-block:: yaml

    name: CI/CD

    on:
      push:
        branches:
          - '**'

    env:
      REGISTRY: ghcr.io
      IMAGE_NAME: ${{ github.repository }}
      STACK_NAME: django-swarm-example

Jobs
++++

Checks
^^^^^^

The workflow proceeds by defining a series of jobs. The first of these is for checks, which stats by checking out the repo (all jobs begin with this), installing python and dependencies, linting with ``black``, and finally running the django project tests. The working directory is set to ``app``, so this job will execute within that directory by default.

To run tests, the ``SECRET_KEY`` environment variable must be set. In order to keep the production secret key from being exposed when running jobs on workflows running from forks, a different ``CI_SECRET_KEY`` is pulled from the GitHub secrets configured above.

.. code-block:: yaml

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
              SECRET_KEY: ${{ secrets.CI_SECRET_KEY }}
            run: python manage.py test --settings=app.settings.ci


Build
^^^^^

Next, we build and push the docker container. By specifying ``needs: [checks]``, we ensure that the checks job has completed before this job is run. This job will also only run on the ``master`` branch.

Each docker image will be tagged with the shortened git commit sha, to prevent ambiguities around using the ``latest`` tag. The short sha is the first 7 characters of the long sha, and could also be obtained by ``git rev-parse --short <commit sha>``. This is set as an environment variable, which is used by `deployment/docker-compose.ci.yml <https://github.com/grahamhoyes/django-docker-swarm-example/blob/master/deployment/docker-compose.ci.yml>`_ to tag the image, along with ``IMAGE_NAME``. It is also set as an output of the job, so that it can be used in the ``deploy`` job, below.

Once the image is built, it is pushed to GitHub packages (by changing the ``REGISTRY`` environment variable and passing different credentials to the ``Docker login`` step, any container registry could be used). In order to do so, we must first log in via the docker client.

``secrets.GITHUB_TOKEN`` is automatically set by the GitHub actions running to be a unique access token, with permissions only for the current repository. ``github.actor`` will be the user who triggers the pipeline, so they must have permissions to push to master and to push repository packages. Once logged in, the image can be pushed and will appear in the `packages of the repo <https://github.com/grahamhoyes/django-docker-swarm-example/packages>`_.

.. code-block:: yaml

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
            GITHUB_SHA_SHORT=$(echo ${{ github.sha }} | cut -c1-7)
            echo "GITHUB_SHA_SHORT=${GITHUB_SHA_SHORT}" >> $GITHUB_ENV
            echo "::set-output name=GITHUB_SHA_SHORT::${GITHUB_SHA_SHORT}"
        - name: Build image
          run: docker-compose -f deployment/docker-compose.ci.yml build
        - name: Docker login
          uses: docker/login-action@v1.10.0
          with:
            registry: ${{ env.REGISTRY }}
            username: ${{ github.actor }}
            password: ${{ secrets.GITHUB_TOKEN }}
        - name: Push image
          run: docker-compose -f deployment/docker-compose.ci.yml push

Deploy
^^^^^^

This is the most complex stage of the workflow. It requires that both the checks and build jobs have completed (listing checks is redundant, since build requires it already). The job will also only be run on ``master``. The working directory is ``deployment``, so every step (except the SCP step, more below) will execute there by default. We extract the short commit sha from the output of the previous job.

.. code-block:: yaml

    deploy:
      runs-on: ubuntu-latest
      needs: [checks, build]
      if: github.ref == 'refs/heads/master'
      defaults:
        run:
          working-directory: deployment
      env:
        GITHUB_SHA_SHORT: ${{ needs.build.outputs.GITHUB_SHA_SHORT }}

We start by installing python and the dependencies again (workspaces aren't preserved between jobs, so we can't reuse the state from the checks job). Then we run ``python manage.py collectstatic``, to collect django's static files into a single directory. This also requires a secret key to be set. Since this job will only be run on pushes to ``master`` of the main repository (not on PRs from forks), we use the actual secret key.


.. code-block:: yaml

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

Next, we set all of the necessary environment variables for the deployment in a ``.env`` file, which are passed by `deployment/docker-compose.prod.yml <https://github.com/grahamhoyes/django-docker-swarm-example/blob/master/deployment/docker-compose.prod.yml>`_ into the django container using the ``env_file`` key.

.. code-block:: yaml

    - name: Set environment variables in .env
      run: |
        echo 'DEBUG=0' >> .env
        echo 'SECRET_KEY=${{ secrets.SECRET_KEY }}' >> .env
        echo 'DB_NAME=${{ secrets.DB_NAME }}' >> .env
        echo 'DB_USER=${{ secrets.DB_USER }}' >> .env
        echo 'DB_PASSWORD=${{ secrets.DB_PASSWORD }}' >> .env
        echo 'DB_HOST=${{ secrets.DB_HOST }}' >> .env
        echo 'DB_PORT=${{ secrets.DB_PORT }}' >> .env
        echo 'REDIS_URI=${{ secrets.REDIS_URI }}' >> .env

The static files are then transferred to the server over scp using `scp-action <https://github.com/appleboy/scp-action>`_, which compresses the files while in transit for efficiency. This action doesn't obey the ``working-directory`` of the job, so we have to use absolute paths.

Files on the server are sent to ``/usr/src/<username>/<repository>``, so make sure the user you are using for SCP/SSH has the necessary permissions. If you change this, make sure to change the nginx config as well. ``strip_components: 1`` removes the first folder in the file path, which in our case strips ``deployment/`` out when sending the files to the server.

.. code-block:: yaml

    - name: Transfer static files to the Swarm manager
      uses: appleboy/scp-action@v0.1.1
      with:
        host: ${{ secrets.SWARM_MANAGER_IP }}
        username: ${{ secrets.SSH_USER }}
        key: ${{ secrets.SSH_PRIVATE_KEY }}
        overwrite: true
        # scp-action doesn't obey working-directory, runs at repo root
        source: "app/static/"
        target: "/usr/src/${{ github.repository }}"
        strip_components: 1

Deployment happens by pointing the docker CLI in the actions runner to the docker engine on the swarm manager over SSH. To do so, we first install the SSH private key for our deploy user on the actions urnner.

.. code-block:: yaml

    - name: Set up SSH
      run: |
        mkdir -p ~/.ssh
        ssh-keyscan -t rsa ${{ secrets.SWARM_MANAGER_IP }} >> ~/.ssh/known_hosts
        echo "${{ secrets.SSH_PRIVATE_KEY }}" >> ~/.ssh/id_rsa
        chmod 600 ~/.ssh/id_rsa

Finally, the actual deploy runs. The ``DOCKER_HOST`` environment variable is set to point the docker CLI to the swarm manager.

First, a ``mkdir`` command is directly executed over SSH to create the media folder for user-uploaded content at ``/var/www/<username>/<repository>/<media>/``. This can be changed by changing this line, and changing the volume mount for the django service in `deployment/docker-compose.prod.yml <https://github.com/grahamhoyes/django-docker-swarm-example/blob/master/deployment/docker-compose.prod.yml>`_.

Optional: Triggering for Pull Requests from Forks
+++++++++++++++++++++++++++++++++++++++++++++++++
