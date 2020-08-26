from django.http import JsonResponse
from app.models import AccessRecord


def home(request):
    AccessRecord.objects.create()
    return JsonResponse({"hits": AccessRecord.objects.count()})
