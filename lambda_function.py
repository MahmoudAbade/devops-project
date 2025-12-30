import json
import os
import urllib3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function triggered by S3 events.
    Publishes event details to Kafka topic.
    """
    
    logger.info(f"Received event: {json.dumps(event)}")
    
    # Get Kafka configuration from environment variables
    kafka_bootstrap_servers = os.environ.get('KAFKA_BOOTSTRAP_SERVERS')
    kafka_topic = os.environ.get('KAFKA_TOPIC', 's3-events')
    
    # Parse S3 event
    for record in event.get('Records', []):
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
        
        # For this implementation, we'll use a simple HTTP endpoint to publish to Kafka
        # In production, you would use kafka-python library
        try:
            # This assumes you have a Kafka REST proxy or custom endpoint
            # For now, we'll just log the message
            logger.info(f"Would publish to Kafka topic '{kafka_topic}': {json.dumps(message)}")
            
            # Note: To actually publish to Kafka, you would need to:
            # 1. Package kafka-python with the Lambda function
            # 2. Configure VPC access to reach Kafka brokers
            # 3. Use KafkaProducer to send messages
            
        except Exception as e:
            logger.error(f"Error publishing to Kafka: {str(e)}")
            raise
    
    return {
        'statusCode': 200,
        'body': json.dumps('S3 event processed successfully')
    }
