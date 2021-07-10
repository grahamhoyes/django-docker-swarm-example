#!/bin/bash

echo "Waiting for the database..."

timeout=60
ready=false

for i in {1..$timeout} do
  if pg_isready -d $DB_NAME -h $DB_HOST -p $DB_PORT -U $DB_USER
  then
    ready=true
    break
  else
    sleep 1
  fi
done

if [ "$ready" = true]
then
  echo "Database connection made"
  exec "$@"
else
  echo "Failed to connect to database"
  return 1
fi
