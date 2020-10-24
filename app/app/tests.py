from django.test import TestCase
import json

from app.models import AccessRecord


class HomePageTestCase(TestCase):
    def test_home_page(self):
        self.assertEqual(AccessRecord.objects.count(), 0)
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(AccessRecord.objects.count(), 1)
        self.assertEqual(
            json.loads(response.content.decode()), {"hits": 1, "cache_hits": 1}
        )
