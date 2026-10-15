# Build stage: install dependencies in a full image
FROM registry.access.redhat.com/ubi9/python-311:latest AS builder

WORKDIR /opt/app-root/src

COPY requirements.txt .
RUN pip install --no-cache-dir --target=/opt/app-root/deps -r requirements.txt

# Runtime stage
FROM registry.access.redhat.com/ubi9/python-311-minimal:latest

COPY --from=builder /opt/app-root/deps /opt/app-root/deps
ENV PYTHONPATH=/opt/app-root/deps

WORKDIR /opt/app-root/src

COPY app.py .
COPY static/ static/

EXPOSE 8080

USER 1001
ENTRYPOINT ["python", "-m", "gunicorn", "--bind", "0.0.0.0:8080", "app:app"]
