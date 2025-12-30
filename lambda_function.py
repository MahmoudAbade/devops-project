import json
import os
import urllib.request
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function triggered by S3 events.
    Publishes event details to Kafka topic via REST Proxy.
    """
    
    logger.info(f"Received event: {json.dumps(event)}")
    
    # Get Kafka configuration from environment variables
    kafka_rest_url = os.environ.get('KAFKA_REST_PROXY_URL')
    kafka_topic = os.environ.get('KAFKA_TOPIC', 's3-events')
    
    if not kafka_rest_url:
        logger.warning("KAFKA_REST_PROXY_URL not set. Skipping publication to Kafka.")

    # Parse S3 event
    for record in event.get('Records', []):
        try:
            bucket_name = record['s3']['bucket']['name']
            object_key = record['s3']['object']['key']
            event_name = record['eventName']
            event_time = record['eventTime']

            # Create message payload
            message = {
                'event_type': 's3_upload',
                'bucket': bucket_name,
                'key': object_key,
                'event_name': event_name,
                'timestamp': event_time,
                'size': record['s3']['object'].get('size', 0)
            }
            
            logger.info(f"Processing S3 event: {json.dumps(message)}")
            
            if kafka_rest_url:
                # Construct the REST Proxy URL for the topic
                # Format: http://host:port/topics/topic_name
                url = f"{kafka_rest_url}/topics/{kafka_topic}"

                # Payload for Kafka REST Proxy v2
                payload = {
                    "records": [
                        {
                            "value": message
                        }
                    ]
                }

                data = json.dumps(payload).encode('utf-8')

                req = urllib.request.Request(url, data=data, method='POST')
                req.add_header('Content-Type', 'application/vnd.kafka.json.v2+json')
                req.add_header('Accept', 'application/vnd.kafka.v2+json')

                try:
                    with urllib.request.urlopen(req, timeout=5) as response:
                        if response.status == 200:
                            logger.info(f"Successfully published to Kafka topic '{kafka_topic}'")
                        else:
                            logger.error(f"Failed to publish to Kafka: HTTP {response.status} {response.read().decode('utf-8')}")
                except Exception as e:
                     logger.error(f"Error calling Kafka REST Proxy: {str(e)}")
            else:
                logger.info(f"Dry run (Kafka not configured): {json.dumps(message)}")

        except Exception as e:
            logger.error(f"Error processing record: {str(e)}")
            # Don't raise, try to process other records

    return {
        'statusCode': 200,
        'body': json.dumps('S3 event processed')
    }
