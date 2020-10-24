from django.http import JsonResponse
from django.views.generic.base import TemplateView
from django.core.cache import cache

from app.models import AccessRecord


def home(request):
    AccessRecord.objects.create()
    # Get the most recent ID, which is much faster than doing .count() once
    # someone writes a bot to curl your site in a loop 100k times
    db_hits = AccessRecord.objects.order_by("-id").first().id

    # Do something with the cache too
    cache_hits = cache.get_or_set("cache-hits", 0)
    cache.incr("cache-hits")
    cache_hits = cache.get("cache-hits")

    return JsonResponse({"hits": db_hits, "cache-hits": cache_hits})


class CoolDogView(TemplateView):
    template_name = "app/cooldog.html"
