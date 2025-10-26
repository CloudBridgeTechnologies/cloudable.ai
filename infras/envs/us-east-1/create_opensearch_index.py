#!/usr/bin/env python3

import boto3
import json
import requests
from requests_aws4auth import AWS4Auth
import sys
import argparse
import os

def get_collection_endpoint(collection_id):
    client = boto3.client('opensearchserverless')
    response = client.batch_get_collection(ids=[collection_id])
    if not response['collectionDetails']:
        raise Exception(f"Collection with ID {collection_id} not found.")
    return response['collectionDetails'][0]['collectionEndpoint']

def create_index(collection_id, index_name):
    # Get OpenSearch endpoint
    collection_endpoint = get_collection_endpoint(collection_id)
    
    # Set up authentication
    region = os.environ.get('AWS_REGION', 'us-east-1')
    service = 'aoss'
    credentials = boto3.Session().get_credentials()
    awsauth = AWS4Auth(credentials.access_key, credentials.secret_key, 
                      region, service, session_token=credentials.token)
    
    # Define index mapping with vector field
    index_mapping = {
        "mappings": {
            "properties": {
                "vector": {
                    "type": "knn_vector",
                    "dimension": 1536,  # Titan embeddings dimension
                    "method": {
                        "name": "hnsw",
                        "space_type": "cosine",
                        "engine": "faiss",
                        "parameters": {
                            "ef_construction": 128,
                            "m": 16
                        }
                    }
                },
                "text": {"type": "text"},
                "metadata": {"type": "object"}
            }
        },
        "settings": {
            "index": {
                "knn": True,
                "knn.algo_param.ef_search": 100
            }
        }
    }
    
    # Create index
    url = f"{collection_endpoint}/{index_name}"
    headers = {'Content-Type': 'application/json'}
    
    print(f"Creating index {index_name} in collection {collection_id}...")
    print(f"Endpoint: {url}")
    
    response = requests.put(url, auth=awsauth, json=index_mapping, headers=headers)
    
    if response.status_code == 200:
        print(f"Successfully created index {index_name}")
        print(response.json())
        return True
    else:
        print(f"Failed to create index. Status code: {response.status_code}")
        print(response.text)
        return False

def main():
    parser = argparse.ArgumentParser(description='Create OpenSearch Serverless index')
    parser.add_argument('--collection-id', required=True, help='OpenSearch Serverless Collection ID')
    parser.add_argument('--index-name', default='default-index', help='Index name to create')
    
    args = parser.parse_args()
    
    success = create_index(args.collection_id, args.index_name)
    if not success:
        sys.exit(1)
    
if __name__ == "__main__":
    main()
