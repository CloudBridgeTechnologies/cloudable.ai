#!/usr/bin/env python3
import boto3
import json
import argparse
import time
import requests
from requests_aws4auth import AWS4Auth

def main():
    parser = argparse.ArgumentParser(description='Create OpenSearch Serverless index')
    parser.add_argument('--tenant', required=True, help='Tenant name (e.g., acme, globex)')
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--env', default='dev', help='Environment (dev, test, prod)')
    args = parser.parse_args()

    tenant = args.tenant
    region = args.region
    env = args.env

    # Get credentials for AWS authentication
    credentials = boto3.Session().get_credentials()
    awsauth = AWS4Auth(
        credentials.access_key,
        credentials.secret_key,
        region,
        'aoss',
        session_token=credentials.token
    )

    # Get the collection info
    aoss_client = boto3.client('opensearchserverless', region_name=region)
    collections = aoss_client.list_collections(
        collectionFilters={
            'name': f'kb-{env}-{tenant}'
        }
    )
    
    if not collections.get('collectionSummaries'):
        print(f"Error: No collection found for kb-{env}-{tenant}")
        return
    
    collection_id = collections['collectionSummaries'][0]['id']
    collection_endpoint = f"https://{collection_id}.{region}.aoss.amazonaws.com"
    
    print(f"Collection found: {collection_id}")
    print(f"Endpoint: {collection_endpoint}")
    
    # Create the default-index with vector mapping
    index_name = "default-index"
    
    # Mapping for the index with vector field
    mapping = {
        "mappings": {
            "properties": {
                "vector": {
                    "type": "knn_vector",
                    "dimension": 1536,  # Dimension for embeddings
                    "method": {
                        "engine": "faiss",
                        "space_type": "l2",
                        "name": "hnsw"
                    }
                },
                "text": {
                    "type": "text"
                },
                "metadata": {
                    "type": "object"
                }
            }
        },
        "settings": {
            "index": {
                "number_of_shards": 1,
                "number_of_replicas": 1
            }
        }
    }
    
    # Create the index with the mapping
    url = f"{collection_endpoint}/{index_name}"
    headers = {'Content-Type': 'application/json'}
    
    try:
        # First check if index exists
        check_response = requests.head(url, auth=awsauth)
        
        if check_response.status_code == 200:
            print(f"Index {index_name} already exists")
        elif check_response.status_code == 404:
            # Create the index
            response = requests.put(url, auth=awsauth, json=mapping, headers=headers)
            
            if response.status_code == 200:
                print(f"Successfully created index {index_name}")
                print(response.json())
            else:
                print(f"Failed to create index. Status code: {response.status_code}")
                print(response.text)
        else:
            print(f"Unexpected status checking index: {check_response.status_code}")
            print(check_response.text)
    except Exception as e:
        print(f"Error creating index: {e}")
    
    # Add a test document to verify everything works
    try:
        doc = {
            "vector": [0.1] * 1536,  # Dummy vector
            "text": "This is a test document for the OpenSearch index",
            "metadata": {
                "source": "test_script",
                "tenant": tenant
            }
        }
        
        doc_url = f"{collection_endpoint}/{index_name}/_doc/test1"
        response = requests.put(doc_url, auth=awsauth, json=doc, headers=headers)
        
        if response.status_code in [200, 201]:
            print(f"Successfully added test document")
            print(response.json())
        else:
            print(f"Failed to add test document. Status code: {response.status_code}")
            print(response.text)
    except Exception as e:
        print(f"Error adding test document: {e}")

if __name__ == "__main__":
    main()
