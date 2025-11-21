import json
import boto3
import os
from datetime import datetime
from urllib.parse import unquote_plus

s3_client = boto3.client('s3')
bedrock_client = boto3.client('bedrock-runtime', region_name='eu-west-1')

BUCKET_NAME = os.environ['BUCKET_NAME']
LLAMA_MODEL = 'eu.meta.llama3-2-1b-instruct-v1:0'

def extract_text_from_pdf(file_content):
    import PyPDF2
    import io
    pdf_reader = PyPDF2.PdfReader(io.BytesIO(file_content))
    text = ""
    for page in pdf_reader.pages:
        text += page.extract_text()
    return text

def extract_text_from_docx(file_content):
    import docx
    import io
    doc = docx.Document(io.BytesIO(file_content))
    text = "\n".join([paragraph.text for paragraph in doc.paragraphs])
    return text

def extract_text_from_txt(file_content):
    return file_content.decode('utf-8')

def get_document_text(bucket, key):
    response = s3_client.get_object(Bucket=bucket, Key=key)
    file_content = response['Body'].read()
    
    if key.lower().endswith('.pdf'):
        return extract_text_from_pdf(file_content)
    elif key.lower().endswith('.docx'):
        return extract_text_from_docx(file_content)
    elif key.lower().endswith('.txt'):
        return extract_text_from_txt(file_content)
    else:
        raise ValueError(f"Unsupported file format: {key}")

def summarize_with_bedrock(document_text):
    prompt_text = "<|begin_of_text|><|start_header_id|>user<|end_header_id|>\n\nSummarize this document concisely.\n\nDocument: " + document_text[:1500] + "<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
    
    body = json.dumps({
        "prompt": prompt_text,
        "max_gen_len": 300,
        "temperature": 0.3,
        "top_p": 0.9
    })
    
    response = bedrock_client.invoke_model(
        modelId=LLAMA_MODEL,
        body=body
    )
    
    response_body = json.loads(response['body'].read())
    return response_body['generation']

def lambda_handler(event, context):
    try:
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            print(f"Processing document: {key}")
            
            document_text = get_document_text(bucket, key)
            summary = summarize_with_bedrock(document_text)
            
            filename = os.path.basename(key)
            name_without_ext = os.path.splitext(filename)[0]
            summary_key = f"summaries/{name_without_ext}_summary.txt"
            
            summary_content = {
                "original_document": filename,
                "summary": summary,
                "timestamp": datetime.utcnow().isoformat(),
                "processed_at": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
            }
            
            s3_client.put_object(
                Bucket=bucket,
                Key=summary_key,
                Body=json.dumps(summary_content, indent=2),
                ContentType='application/json'
            )
            
            print(f"Summary saved to: {summary_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Document summarization completed successfully')
        }
    
    except Exception as e:
        print(f"Error: {str(e)}")
        raise e
