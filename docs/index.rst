.. Deploying Django with Docker Swarm documentation master file, created by
   sphinx-quickstart on Thu Jul  8 17:27:42 2021.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

Deploying Django with Docker Swarm
=======================================================

An example project for deploying Django on Docker Swarm.

This originally began as a playground and documentation for `IEEE UofT's <https://ieee.utoronto.ca>`_ development needs to serve our `hackathon template <https://github.com/ieeeuoft/hackathon-template>`_. As such, the original requirements were:

* Runs on a single server, but the option to add more nodes in the future is preferred
* Postgres is installed natively on the server
* Nginx is installed natively on the server, handling SSL and static file serving
* The application should be deployed as a docker container than Nginx can reverse proxy to

To begin, fork `the grahamhoyes/django-docker-swarm-example <https://github.com/grahamhoyes/django-docker-swarm-example>`_ repository, and clone it locally. This example will make use of GitHub `Actions <https://github.com/features/actions>`_ and `Packages <https://github.com/features/packages>`_. These are free (with some limitations) for public repositories, so I recommend you keep your fork public.

Start by reading about :ref:`the Django project<The Project>` that this example uses. From there, follow the pages to configure servers, github actions, and the deployment.

Credits
-------

The following resources were a great help in developing this example:

* https://github.com/testdrivenio/django-github-digitalocean
* https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
* https://github.com/appleboy/scp-action
* https://github.com/appleboy/ssh-action
* https://stackoverflow.com/questions/47941075/host-django-on-subfolder/47945170#47945170
* https://github.com/sudo-bmitch/docker-stack-wait

Index
-----

.. toctree::
   :maxdepth: 2

   theproject
   serversetup
   deploymentconfig