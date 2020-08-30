from django.http import JsonResponse
from app.models import AccessRecord


def home(request):
    AccessRecord.objects.create()
    # Get the most recent ID, which is much faster than doing .count() once
    # someone writes a bot to curl your site in a loop 100k times
    return JsonResponse({"hits": AccessRecord.objects.order_by("-id").first().id})
