#!/bin/bash

echo "Waiting for the database..."

while ! nc -z $DATABASE_HOST $DATABASE_PORT; do
  sleep 0.1
done

echo "Database connection made"

exec "$@"