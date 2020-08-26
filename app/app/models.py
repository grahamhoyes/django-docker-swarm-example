from django.db import models


class AccessRecord(models.Model):
    when = models.DateTimeField(auto_now=True, null=False)
