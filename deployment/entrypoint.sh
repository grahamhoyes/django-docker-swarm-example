#!/bin/bash

echo "Waiting for the database..."

TIMEOUT=60
ATTEMPT=0
command="pg_isready -d $DB_NAME -h $DB_HOST -p $DB_PORT -U $DB_USER"

until [ "$ATTEMPT" -eq "$TIMEOUT" ] || eval $command; do
  (( ATTEMPT++ ))
  sleep 1
done

if [ "$ATTEMPT" -lt "$TIMEOUT" ]
then
  echo "Database connection made"
  exec "$@"
else
  echo "Failed to connect to database"
  exit 1
fi
