import json
import boto3
import os
import base64
from datetime import datetime
import uuid

s3_client = boto3.client('s3')
BUCKET_NAME = os.environ['BUCKET_NAME']

def lambda_handler(event, context):
    try:
        body = json.loads(event.get('body', '{}'))
        
        filename = body.get('filename')
        file_content = body.get('file_content')
        
        if not filename or not file_content:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Missing filename or file_content'})
            }
        
        file_data = base64.b64decode(file_content)
        
        document_id = str(uuid.uuid4())
        s3_key = f"uploads/{document_id}_{filename}"
        
        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=s3_key,
            Body=file_data
        )
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'message': 'Document uploaded successfully',
                'document_id': document_id,
                'filename': filename,
                's3_key': s3_key,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
    
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }
