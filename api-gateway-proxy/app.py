from flask import Flask, request, jsonify
from kafka import KafkaProducer
import json
import logging
import os

app = Flask(__name__)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Kafka configuration
KAFKA_BOOTSTRAP_SERVERS = os.environ.get('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092')
KAFKA_TOPIC = os.environ.get('KAFKA_TOPIC', 'api-events')

# Create Kafka producer
producer = KafkaProducer(
    bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS.split(','),
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy'}), 200

@app.route('/publish', methods=['POST'])
def publish_event():
    """Publish event to Kafka"""
    try:
        # Get request data
        data = request.get_json()
        
        if not data:
            return jsonify({'error': 'No data provided'}), 400
        
        # Add metadata
        event = {
            'data': data,
            'source': 'api-gateway',
            'headers': dict(request.headers)
        }
        
        # Publish to Kafka
        future = producer.send(KAFKA_TOPIC, value=event)
        result = future.get(timeout=10)
        
        logger.info(f"Published event to Kafka: {event}")
        
        return jsonify({
            'status': 'success',
            'message': 'Event published to Kafka',
            'topic': KAFKA_TOPIC,
            'partition': result.partition,
            'offset': result.offset
        }), 200
        
    except Exception as e:
        logger.error(f"Error publishing event: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/events', methods=['POST'])
def receive_event():
    """Receive event from API Gateway"""
    return publish_event()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
