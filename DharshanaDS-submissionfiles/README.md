# Simple Extraction Django App Deployment on Minikube

This document explains all the steps followed to containerize, configure, and deploy a Django-based extraction application using Docker and Kubernetes on Minikube. It includes the complete configuration and file contents used during the setup.

---

## Project Structure

```
Simple-Extraction-Demo-Track/
├── Dockerfile
├── docker-entrypoint.sh
├── requirements.txt
├── manage.py
├── core/
├── extraction/
├── k8s/
│   ├── django-deployment.yaml
│   ├── django-service.yaml
│   ├── postgres-deployment.yaml
│   ├── postgres-service.yaml
│   ├── ingress.yaml
│   └── secret.yaml
├── static/
├── templates/
└── README.md
```

---

## Prerequisites

* Docker
* Minikube
* kubectl
* Python 3.10+
* Virtualenv (optional)

---

## Step-by-Step Deployment Instructions

### Step 1: Create Dockerfile

Create a `Dockerfile` with the following content:

```dockerfile
FROM python:3.10-slim

ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

WORKDIR /app

RUN apt-get update && apt-get install -y \
    libpq-dev \
    gcc \
    netcat-openbsd \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

COPY . .

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 8000

ENTRYPOINT ["/docker-entrypoint.sh"]
```

### Step 2: Create Entrypoint Script

Create `docker-entrypoint.sh` with the following content:

```bash
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
```

### Step 3: Build the Docker Image

```bash
docker build -t yourproject:latest .
```

### Step 4: Start Minikube

```bash
minikube start
```

### Step 5: Load Docker Image into Minikube

```bash
minikube image load yourproject:latest
```

### Step 6: Enable Ingress Controller

```bash
minikube addons enable ingress
```

### Step 7: Add Host Mapping

```bash
echo "$(minikube ip) demo.local" | sudo tee -a /etc/hosts
```

### Step 8: Create Kubernetes Secrets

Create `k8s/secret.yaml` with the following content:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: django-secret
type: Opaque
stringData:
  SECRET_KEY: wt(0-q$rj3r5$3q^8k(kv6r^_92$@daka_)+6xlga*j0w85!u^
  DB_NAME: extraction_db
  DB_USER: extraction_user
  DB_PASSWORD: strongpassword123
  DEBUG: "False"
  ALLOWED_HOSTS: demo.local
```

### Step 9: Create PostgreSQL Deployment

Create `k8s/postgres-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          valueFrom:
            secretKeyRef:
              name: django-secret
              key: DB_NAME
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: django-secret
              key: DB_USER
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: django-secret
              key: DB_PASSWORD
        volumeMounts:
        - name: pgdata
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: pgdata
        persistentVolumeClaim:
          claimName: postgres-pvc
```

### Step 10: Create PostgreSQL Service

Create `k8s/postgres-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  ports:
    - port: 5432
  selector:
    app: postgres
  clusterIP: None
```

### Step 11: Create Django Deployment

Create `k8s/django-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: django
spec:
  replicas: 1
  selector:
    matchLabels:
      app: django
  template:
    metadata:
      labels:
        app: django
    spec:
      containers:
      - name: django
        image: yourproject:latest
        imagePullPolicy: Never
        ports:
        - containerPort: 8000
        env:
        - name: DB_HOST
          value: postgres
        - name: DB_PORT
          value: "5432"
        - name: DB_NAME
          valueFrom:
            secretKeyRef:
              name: django-secret
              key: DB_NAME
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: django-secret
              key: DB_USER
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: django-secret
              key: DB_PASSWORD
        - name: DEBUG
          valueFrom:
            secretKeyRef:
              name: django-secret
              key: DEBUG
        - name: ALLOWED_HOSTS
          valueFrom:
            secretKeyRef:
              name: django-secret
              key: ALLOWED_HOSTS
        - name: SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: django-secret
              key: SECRET_KEY
        readinessProbe:
          httpGet:
            path: /
            port: 8000
          initialDelaySeconds: 10
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /
            port: 8000
          initialDelaySeconds: 20
          periodSeconds: 10
```

### Step 12: Create Django Service

Create `k8s/django-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: django-service
spec:
  selector:
    app: django
  ports:
  - protocol: TCP
    port: 8000
    targetPort: 8000
  type: ClusterIP
```

### Step 13: Create Ingress Resource

Create `k8s/ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: django-ingress
  annotations: {}
spec:
  rules:
  - host: demo.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: django-service
            port:
              number: 8000
```

### Step 14: Apply All Kubernetes Resources

```bash
kubectl apply -f k8s/
```

### Step 15: Verify Deployed Resources

```bash
kubectl get pods
kubectl get svc
kubectl get ingress
```

### Step 16: Access the Application

Open a browser and navigate to:

```
http://demo.local
```

Or use curl:

```bash
curl -H "Host: demo.local" http://$(minikube ip)
```

---

## Troubleshooting

* Ensure the ingress addon is enabled and host entry exists in `/etc/hosts`
* Check logs using `kubectl logs <pod-name>` for startup issues
* Confirm secret keys and service names are correctly referenced

---

## Author

Dharshana DS
Cloud Engineer Project - Habot Evaluation
