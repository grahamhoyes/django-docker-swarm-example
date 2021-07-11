.. _The Project:

The Django Project
==================

The Django project used in this tutorial is a simple application that counts the number of times the landing page has been visited. The project code is entirely contained within the `app/app <https://github.com/grahamhoyes/django-docker-swarm-example/tree/master/app/app>`_ directory. This is somewhat non-standard for Django: our project name is ``app``, but we have included our views, models, and migrations under the project directory as well, rather than creating a separate Django application (which for lack of a batter name, would have been called... app).

The relevant portions of the project directory structure are::

   .
   ├── app
   │   ├── admin.py
   │   ├── migrations/
   │   ├── models.py
   │   ├── settings
   │   │   ├── __init__.py
   │   │   └── ci.py
   │   ├── static
   │   │   └── app
   │   │       └── dog.jpg
   │   ├── templates
   │   │   └── app
   │   │       └── cooldog.html
   │   ├── tests.py
   │   ├── urls.py
   │   ├── views.py
   │   └── wsgi.py
   ├── manage.py
   └── requirements.txt

There are a few key elements to the project, which let us test desired functionality:

* The models, to interact with a postgres database.
* A cache, configured to use Redis. This will be deployed as part of our Docker stack.
* A view that interacts with the models and the cache.
* A view that uses static files, to verify that they are deployed properly.
* A model that lets us upload a photo via the admin site, to confirm that user-uploaded content works.
* Unit tests, to be run by Github Actions as our CI/CD platform.

The project has two simple models:

.. code-block:: python

   # app/models.py
   from django.db import models


   class AccessRecord(models.Model):
       when = models.DateTimeField(auto_now=True, null=False)


   class PhotoRecord(models.Model):
       """
       Store an image to test media uploads
       """

       image = models.ImageField(upload_to="uploads/")
       modified_at = models.DateTimeField(auto_now=True)

``AccessRecord`` contains just a primary key field, and an auto-generated timestamp. The ``PhotoRecord`` model isn't used in any views, but is hooked up to the Admin site to verify that media uploads are working.

The views are likewise simple:

.. code-block:: python

   # app/views.py
   from django.http import JsonResponse
   from django.views.generic.base import TemplateView
   from django.core.cache import cache

   from app.models import AccessRecord


   def home(request):
       AccessRecord.objects.create()
       db_hits = AccessRecord.objects.order_by("-id").first().id

       # Do something with the cache too
       cache_hits = cache.get_or_set("cache-hits", 0)
       cache.incr("cache-hits")
       cache_hits = cache.get("cache-hits")

       return JsonResponse({"hits": db_hits, "cache-hits": cache_hits})


   class CoolDogView(TemplateView):
       template_name = "app/cooldog.html"

The ``home`` view creates a new ``AccessRecord`` (which has its ``when`` field auto-populated), and returns the highest ``id`` in the database, indicating how many hits there were. It uses the cache to increment a value, which defaults to 0. When visiting the home page after around 10 minutes, ``cache-hits`` will be reset to 0, but ``db_hits`` is persistent with the database.

``CoolDogView`` renders an HTML page with an image of a cool dog, stored under ``app/static/``.

.. |DefaultSettings| replace:: ``settings/__init__.py``
.. _DefaultSettings: https://github.com/grahamhoyes/django-docker-swarm-example/blob/master/app/app/settings/__init__.py

.. |CiSettings| replace:: ``settings/ci.py``
.. _CiSettings: https://github.com/grahamhoyes/django-docker-swarm-example/blob/master/app/app/settings/ci.py

The typical Django ``settings.py`` file is broken out into a settings module, with default values for normal operation in |DefaultSettings|_, and overrides for a testing environment in |CiSettings|_. These CI overrides replace the database configuration to point to an in-memory SQLite database instead of Postgres, and replace the cache configuration with an in-memory cache instead of Redis. This simplifies the process of running unit tests in a CI runner, as we do not need to bring up containers for the database or cache.

Environment Variables
---------------------

The table below lists the environment variables the project looks for in the default settings file (|DefaultSettings|_). Only setting ``SECRET_KEY`` is required, the rest all have defaults which should be suitable for running locally.

.. list-table::
    :widths: 1 3
    :header-rows: 1

    * - Variable
      - Description
    * - ``SECRET_KEY``
      - The Django `secret key <https://docs.djangoproject.com/en/2.2/ref/settings/#std:setting-SECRET_KEY>`_. In production, this must be kept secret. This environment variable must always be explicitly set (to prevent accidentally using a generic default), but locally it can be any value.
    * - ``DB_NAME``
      - Database name. Defaults to ``djangodb``.
    * - ``DB_USER``
      - Database user. Defaults to ``postgres``.
    * - ``DB_PASSWORD``
      - Database password. Defaults to an empty string.
    * - ``DB_HOST``
      - Database host. Defaults to 127.0.0.1.
    * - ``DB_PORT``
      - Database port. Defaults to 5432.
    * - ``REDIS_URI``
      - Redis URI. Defaults to ``127.0.0.1:6379/1``.

Running Locally
---------------
Configurations for running locally are within the `development <https://github.com/grahamhoyes/django-docker-swarm-example/tree/master/development>`_ folder, with the exception of ``docker-compose.yml``, which is located in the repository root. This is largely for convenience, and so that containers derive their names from the name of the folder the repository was cloned in to.

``docker-compose.yml`` defines 3 services:

``postgres``
   Uses the ``postgres:12.2`` image (newer versions should also work). Postgres is exposed on port 5432, and by default will use the database name ``djangodb`` unless the ``DB_NAME`` environment variable is set.

   Data is persisted using the ``django-swarm-example_postgres-data`` volume. I recommend giving your volumes a project-specific name, so that similar configs between projects will still have independent database data folders.

``redis``
   Uses the ``redis:6-alpine`` image, exposed on port 6379.

``django``
   The container which runs the Django development server on port 8000. By using a volume mount for the ``app`` directory, hot-reloading is enabled.

   Environment variables for database and redis credentials are passed through to the container, with suitable defaults. The only environment variable that does not have a default is ``SECRET_KEY``, which you must first set yourself.

First, set the secret key environment variable:

.. code:: console

   $ export SECRET_KEY=123456

To build the container, from within the repository root:

.. code:: console

   $ docker-compose build

To run the project:

.. code:: console

   $ docker-compose up

This will start the Postgres, Redis, and Django containers, the latter of which will wait for Postgres to be available (via the `entrypoint.sh <https://github.com/grahamhoyes/django-docker-swarm-example/blob/master/development/entrypoint.sh>`_). The django service will run migrations as soon as the postgres connection is established.

Once all containers are up, you can access the server at http://localhost:8000/. The first time you visit, you should see ``{"hits": 1, "cache-hits": 1}``. The counters will increase with every subsequent visit, with the cache hits resetting after about 10 minutes of inactivity.

Configuration for Deployment
----------------------------

The project is almost entirely ready for deployment as-is, since most configuration options are pulled in as environment variables. You will, however, need to set the ``ALLOWED_HOSTS`` setting in the main settings file to include your domain. In this example, we use ``django-swarm-example.grahamhoyes.com``. A domain is highly recommended so that letsencrypt can be used for SSL certificates later on, but you can also substitute with your server's public IP address:

.. code-block:: python

    # app/settings/__init__.py
    ...
    if DEBUG:
        ALLOWED_HOSTS = ["localhost", "127.0.0.1"]
    else:
        # Include your domain or IP address here
        ALLOWED_HOSTS = ["django-swarm-example.grahamhoyes.com"]