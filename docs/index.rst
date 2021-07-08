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

The Django Project
------------------

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

The ``home`` view creates a new ``AccessRecord`` (which has its ``when`` field auto-populated), and returns the highest ``id``, indicating how many hits there were. It uses the cache to increment a value, which defaults to 0. When visiting the home page after a few hours, ``cache-hits`` will be reset to 0, but ``db_hits`` is persistent with the database.

``CoolDogView`` renders an HTML page with an image of a cool dog, stored under ``app/static/``.

.. |DefaultSettings| replace:: ``settings/__init__.py``
.. _DefaultSettings: https://github.com/grahamhoyes/django-docker-swarm-example/blob/master/app/app/settings/__init__.py

.. |CiSettings| replace:: ``settings/ci.py``
.. _CiSettings: https://github.com/grahamhoyes/django-docker-swarm-example/blob/master/app/app/settings/ci.py

The typical Django ``settings.py`` file is broken out into a settings module, with default values for normal operation in |DefaultSettings|_, and overrides for a testing environment in |CiSettings|_. These CI overrides replace the database configuration to point to an in-memory SQLite database instead of Postgres, and replace the cache configuration with an in-memory cache instead of Redis. This simplifies the process of running unit tests in a CI runner, as we do not need to bring up containers for the database or cache.

Running Locally
---------------
Configurations for running locally are within the `development <https://github.com/grahamhoyes/django-docker-swarm-example/tree/master/development>`_ folder. For this tutorial, we assume a familiarity with running Django locally normally, and instead explain how to run it through docker.

To build the container, from within the repository root:

.. code-block: python

   import foo

