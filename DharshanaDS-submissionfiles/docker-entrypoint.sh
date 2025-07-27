#!/bin/bash

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be available..."
until nc -z $DB_HOST $DB_PORT; do
  sleep 1
done
echo "PostgreSQL is available"

# Run database migrations
echo "Applying database migrations..."
python manage.py migrate

# Collect static files
echo "Collecting static files..."
python manage.py collectstatic --noinput

# Start the Django app
echo "Starting Django server..."
exec gunicorn core.wsgi:application --bind 0.0.0.0:8000
