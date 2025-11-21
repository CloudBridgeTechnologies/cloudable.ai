#!/usr/bin/env python3

import boto3
import json
import requests
import sys
import os
from requests_aws4auth import AWS4Auth

def get_collection_endpoint(collection_id, region):
    client = boto3.client('opensearchserverless', region_name=region)
    response = client.batch_get_collection(ids=[collection_id])
    if not response['collectionDetails']:
        raise Exception(f"Collection with ID {collection_id} not found.")
    return response['collectionDetails'][0]['collectionEndpoint']

def create_index(collection_id, index_name, region):
    # Get OpenSearch endpoint
    collection_endpoint = get_collection_endpoint(collection_id, region)
    print(f"Collection endpoint: {collection_endpoint}")
    
    # Set up authentication
    service = 'aoss'
    credentials = boto3.Session().get_credentials()
    awsauth = AWS4Auth(credentials.access_key, credentials.secret_key, 
                      region, service, 
                      session_token=credentials.token)
    
    # Prepare index mapping
    index_mapping = {
        "mappings": {
            "properties": {
                "vector": {
                    "type": "knn_vector",
                    "dimension": 1536,
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
    
    # Create the index
    # Remove https:// if it's already in the endpoint
    if collection_endpoint.startswith('https://'):
        url = f'{collection_endpoint}/{index_name}'
    else:
        url = f'https://{collection_endpoint}/{index_name}'
    print(f"Creating index at URL: {url}")
    
    try:
        response = requests.put(
            url,
            auth=awsauth,
            json=index_mapping,
            headers={"Content-Type": "application/json"}
        )
        print(f"Response status: {response.status_code}")
        print(f"Response body: {response.text}")
        response.raise_for_status()
        return True
    except Exception as e:
        print(f"Error creating index: {e}")
        return False

def main():
    if len(sys.argv) != 4:
        print("Usage: create_index.py <collection_id> <index_name> <region>")
        sys.exit(1)
    
    collection_id = sys.argv[1]
    index_name = sys.argv[2]
    region = sys.argv[3]
    
    print(f"Creating index {index_name} in collection {collection_id} in region {region}")
    success = create_index(collection_id, index_name, region)
    if success:
        print(f"Successfully created index {index_name}")
        sys.exit(0)
    else:
        print(f"Failed to create index {index_name}")
        sys.exit(1)

if __name__ == "__main__":
    main()
