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

.. toctree::
   :maxdepth: 2
   :caption: Contents:




