Deployment Configuration
========================

For this example, we use GitHub repository secrets to manage our deployment secrets, and GitHub Actions to run the deployment pipeline. You could substitute these for a CI runner of your choice (CircleCI, Jenkins, etc).

.. _secrets:

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

Files on the server are sent to ``/usr/src/<username>/<repository>``, so make sure the user you are using for SCP/SSH has the necessary permissions. If you change this, make sure to change the nginx config as well. ``strip_components: 1`` removes the first folder in the file path, which in our case strips ``app/`` out when sending the files to the server.

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

Deployment happens by pointing the docker CLI in the actions runner to the docker engine on the swarm manager over SSH. To do so, we first install the SSH private key for our deploy user on the actions runner.

.. code-block:: yaml

    - name: Set up SSH
      run: |
        mkdir -p ~/.ssh
        ssh-keyscan -t rsa ${{ secrets.SWARM_MANAGER_IP }} >> ~/.ssh/known_hosts
        echo "${{ secrets.SSH_PRIVATE_KEY }}" >> ~/.ssh/id_rsa
        chmod 600 ~/.ssh/id_rsa

Finally, the actual deploy runs. The ``DOCKER_HOST`` environment variable is set to point the docker CLI to the swarm manager.

First, we log in to GitHub packages with docker, this time manually instead of using an action. To use a different container registry, change the registry, username, and password here as well.

We then bring up the deployment with ``docker stack deploy``, using `deployment/docker-compose.prod.yml <https://github.com/grahamhoyes/django-docker-swarm-example/blob/master/deployment/docker-compose.prod.yml>`_ as the stack. ``--with-registry-auth`` passes the GitHub packages credentials to swarm nodes so they can pull the image. ``--prune`` removes old containers after the deploy succeeds.

After launching the stack, the workflow waits up to 300 seconds for the stack to deploy using `docker-stack-wait <https://github.com/sudo-bmitch/docker-stack-wait>`_. The shell script is included as part of this repository, rather than pulling it from an external source while running.

Finally, migrations are ran. This currently uses a workaround, since there is a bug preventing running ``docker-compose exec`` with a docker host over SSH. Because we are running the container directly with ``docker run``, the container lives outside of the swarm bridge network, on the regular docker bridge network. This is why we allowed ``172.17.0.1`` when :ref:`configuring postgres connection rules <configure-connection-rules>`.

.. code-block:: yaml

    - name: Bring up deployment
      env:
        DOCKER_HOST: ssh://${{ secrets.SSH_USER }}@${{ secrets.SWARM_MANAGER_IP }}
      run: |
        echo "Logging in to GitHub packages..."
        echo ${{ secrets.GITHUB_TOKEN }} | docker login ${{ env.REGISTRY }} -u ${{ github.actor }} --password-stdin

        echo "Bringing up deployment..."
        docker stack deploy --prune --with-registry-auth -c docker-compose.prod.yml ${{ env.STACK_NAME }}

        echo "Waiting for deployment..."
        sleep 30
        ./docker-stack-wait.sh -t 300 ${{ env.STACK_NAME }}

        echo "Running migrations..."
        # TODO: It would be better to use docker-compose against the django service,
        # but there is currently a bug in docker-compose preventing running services
        # over an SSH host.
        IMAGE=${REGISTRY}/${IMAGE_NAME}/django-app:${GITHUB_SHA_SHORT}
        docker run --rm --env-file .env ${IMAGE} python manage.py migrate


Optional: Triggering for Pull Requests from Forks
+++++++++++++++++++++++++++++++++++++++++++++++++

In an open source project, you will probably want pull requests from forks to also run the checks stage. To do that, I recommend splitting the workflow above into two files: ``main.yml`` and ``deploy.yml``.

``deploy.yml`` should be the same as the workflow described above, with some minor changes:

* Change the branch pattern at the top of the workflow to just ``'master'`` instead of ``'**'``
* Remove the ``checks`` job entirely
* For cleanliness, remove the ``if: github.ref == 'refs/heads/master'`` line from the ``build`` and ``deploy`` jobs, since that is covered by the updated branch pattern.

``checks.yml`` should only contain the ``checks`` job, and does not need the ``env`` section at the top of the default workflow. To allow secrets to be passed to PRs running from forks, change the top section to:

.. code-block:: yaml

    on:
      pull_request_target:
        branches:
          - '**'

The ``pull_request_target`` event runs in the base context of the pull request, rather than the merge commit. This prevents forks from modifying the workflow to just print out your secrets. You can read more about it `here <https://docs.github.com/en/actions/reference/events-that-trigger-workflows#pull_request_target>`_.

We want the workflow to run in the context of the base repository (i.e, using the workflow from the base repository), but we still want it to check out code from the fork. To do that, we need to update the checkout step:

.. code-block:: yaml

    steps:
      - uses: actions/checkout@v2
        with:
          ref: ${{github.event.pull_request.head.ref}}

With that change, the ``checks.yml`` workflow will run code from pull requests using the workflow in the base repository. ``deploy.yml`` will only run on pushes to the ``master`` branch, using the workflow from the merge commit.

Post-Deploy
-----------

Creating an Admin User
++++++++++++++++++++++

After deploying, you will probably want to create an admin user to log in to the admin site with. The easiest way to do this is to run ``python manage.py createsuperuser`` inside the django container that was deployed on the swarm manager.

To do that, SSH into your swarm manager, and run the following to print to container ID of the django container. ``<stack_name>`` is whatever stack name you have set in the workflow file, for this example it is ``django-swarm-example``.

.. code-block:: console

    $ docker ps --filter name='<stack_name>_django' -q

Once you have the container ID (which you could also just read from the output of ``docker ps``), run the command to create a superuser:

.. code-block:: console

    $ docker exec -it <container id> python manage.py createsuperuser

You should now be able to visit ``<yourdomain>/admin``, and log in with the newly created account.