FROM python:3.12-slim

RUN useradd -m -u 1001 appuser

WORKDIR /app
COPY app.py .

RUN chown -R appuser:appuser /app

USER appuser

EXPOSE 8080

CMD ["python", "app.py"]
