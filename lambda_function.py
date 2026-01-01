import json
import urllib.request
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Handles S3 events and API Gateway events, forwarding them to Kafka via REST Proxy.
    """
    kafka_rest_url = os.environ.get('KAFKA_REST_URL') # e.g., http://<EC2_IP>:8082
    
    if not kafka_rest_url:
        logger.error("KAFKA_REST_URL not set")
        return {"statusCode": 500, "body": "Configuration Error"}

    records_to_send = []

    # 1. Handle S3 Events
    if 'Records' in event and 's3' in event['Records'][0]:
        topic = "s3-events"
        for record in event['Records']:
            payload = {
                "source": "s3",
                "bucket": record['s3']['bucket']['name'],
                "key": record['s3']['object']['key'],
                "time": record['eventTime']
            }
            records_to_send.append((topic, payload))

    # 2. Handle API Gateway Events (HTTP API payload)
    elif 'routeKey' in event or 'rawPath' in event:
        topic = "api-events"
        body = event.get('body', '{}')
        try:
            body_json = json.loads(body) if body else {}
        except:
            body_json = {"raw": body}

        payload = {
            "source": "api-gateway",
            "path": event.get('rawPath'),
            "data": body_json
        }
        records_to_send.append((topic, payload))

    # Fallback/Test
    else:
        topic = "api-events"
        records_to_send.append((topic, {"source": "unknown", "raw": event}))

    # Send to Kafka REST
    for topic, payload in records_to_send:
        url = f"{kafka_rest_url}/topics/{topic}"
        headers = {
            "Content-Type": "application/vnd.kafka.json.v2+json",
            "Accept": "application/vnd.kafka.v2+json"
        }
        data = json.dumps({"records": [{"value": payload}]}).encode('utf-8')

        try:
            req = urllib.request.Request(url, data=data, headers=headers, method='POST')
            with urllib.request.urlopen(req, timeout=3) as res:
                logger.info(f"Sent to {topic}: {res.status}")
        except Exception as e:
            logger.error(f"Failed to send to {topic} at {url}: {e}")
            # Don't fail the Lambda, just log. Setup might be starting up.

    return {"statusCode": 200, "body": "Processed"}
