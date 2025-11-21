#!/bin/bash

cd lambda

echo "Building summarizer package..."
mkdir -p package
pip install -r requirements.txt -t package/
cp summarizer.py package/
cd package
zip -r ../summarizer.zip .
cd ..
rm -rf package

echo "Building upload handler package..."
mkdir -p package
cp upload_handler.py package/
cd package
zip -r ../upload_handler.zip .
cd ..
rm -rf package

echo "Building summary retriever package..."
mkdir -p package
cp summary_retriever.py package/
cd package
zip -r ../summary_retriever.zip .
cd ..
rm -rf package

echo "Lambda packages created successfully!"
