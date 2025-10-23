# API Key Authentication

This document describes the implementation of API key authentication for the Cloudable.AI platform.

## Overview

API key authentication has been implemented on all API endpoints to ensure secure access to the platform's services. This authentication layer helps to:

- Control access to API resources
- Track and manage API usage
- Apply rate limiting and throttling
- Prevent unauthorized access

## Implementation Details

### Infrastructure Components

- **API Gateway REST API**: Secured with API key authentication requirement
- **API Keys**: Managed through API Gateway, linked to usage plans
- **Usage Plans**: Define throttling and quota limits
- **WAF Integration**: Additional layer of protection against common attacks

### Key Configuration Elements

- API keys are required for all endpoints
- Throttling is set to 10 requests per second with a burst limit of 20
- Daily quota limit of 10,000 requests per API key
- WAF protection against SQL injection and common web vulnerabilities
- Rate-based limiting at the WAF level to prevent DDoS attacks

## Testing Results

Security testing confirms that:

1. Requests with valid API keys receive proper responses
2. Requests without API keys are rejected with a 403 Forbidden status
3. Rate limiting and throttling work as expected

## API Key Management

API keys can be managed through:

1. AWS Console:
   - Navigate to API Gateway > API Keys
   - Keys can be created, viewed, rotated, and deleted

2. Terraform:
   - Keys are defined in `api-gateway.tf`
   - Output as sensitive value in Terraform output

## Using the API Key

To make authenticated requests:

```bash
curl -X POST "https://api.cloudable.ai/chat" \
  -H "Content-Type: application/json" \
  -H "x-api-key: YOUR_API_KEY" \
  -d '{"tenant_id":"t001","customer_id":"c001","message":"Hello"}'
```

## Security Best Practices

1. **Store API keys securely**: Never commit API keys to source code repositories
2. **Rotate keys periodically**: Implement a key rotation policy
3. **Monitor usage**: Set up CloudWatch alarms for unusual usage patterns
4. **Apply least privilege**: Create different keys with different permissions as needed
5. **Use API key alongside IAM for internal services**: For added security

## Additional Resources

- `test-api.sh`: Script to test API endpoints with and without authentication
- `API_SECURITY_TEST_RESULTS.md`: Detailed test results
- AWS Documentation: [Using API Keys with REST APIs](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-api-key-custom-domain.html)
