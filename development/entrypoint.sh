#!/bin/bash

echo "Waiting for the database..."

while ! pg_isready -d $DB_NAME -h $DB_HOST -p $DB_PORT -U $DB_USER; do
  sleep 0.1
done

echo "Database connection made"

echo "Running migrations..."
python manage.py migrate
echo "Done migrations"

exec "$@"