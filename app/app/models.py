from django.db import models


class AccessRecord(models.Model):
    when = models.DateTimeField(auto_now=True, null=False)


class PhotoRecord(models.Model):
    """
    Store an image to test media uploads
    """
    image = models.ImageField(upload_to="uploads/")
    modified_at = models.DateTimeField(auto_now=True)
