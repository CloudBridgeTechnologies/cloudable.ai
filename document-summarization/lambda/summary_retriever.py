import json
import boto3
import os

s3_client = boto3.client('s3')
BUCKET_NAME = os.environ['BUCKET_NAME']

def lambda_handler(event, context):
    try:
        document_name = event.get('pathParameters', {}).get('documentName')
        
        if not document_name:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Missing documentName parameter'})
            }
        
        summary_key = f"summaries/{document_name}_summary.txt"
        
        try:
            response = s3_client.get_object(Bucket=BUCKET_NAME, Key=summary_key)
            summary_content = response['Body'].read().decode('utf-8')
            summary_data = json.loads(summary_content)
            
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(summary_data)
            }
        
        except Exception as e:
            if 'NoSuchKey' in str(e):
                return {
                    'statusCode': 404,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({
                        'error': 'Summary not found',
                        'message': f'No summary exists for document: {document_name}'
                    })
                }
            else:
                return {
                    'statusCode': 500,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({'error': str(e)})
                }
    
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }
