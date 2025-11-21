# Enhanced Langfuse Monitoring for Cloudable.AI

This document provides a comprehensive guide to the enhanced Langfuse monitoring features implemented for Cloudable.AI. These tools provide deep observability, evaluation, and testing capabilities for LLM operations across the platform.

## Overview

We've expanded the basic Langfuse integration with advanced monitoring features including:

1. **Real-time Metrics Dashboard** - Visualize Langfuse metrics locally
2. **LLM Quality Evaluations** - Automated evaluation of response quality
3. **Load Testing with Observability** - Stress test the system while monitoring performance
4. **Automated Reporting** - Generate PDF reports from Langfuse metrics

## 1. Metrics Dashboard

The `langfuse_metrics_dashboard.py` script provides a local dashboard for visualizing Langfuse metrics:

```bash
python langfuse_metrics_dashboard.py \
  --public-key YOUR_LANGFUSE_PUBLIC_KEY \
  --secret-key YOUR_LANGFUSE_SECRET_KEY \
  --days 7 \
  --serve
```

Features:
- Visualize traces by type and tenant
- Chart generation model usage
- Track quality scores over time
- Interactive local HTTP server mode
- Export visualizations for sharing

## 2. LLM Quality Evaluations

The `langfuse_evaluations.py` module implements automated evaluation metrics for response quality:

```python
# In your Lambda function
if LANGFUSE_ENABLED and EVALUATIONS_ENABLED:
    evaluation_scores = langfuse_evaluations.evaluate_chat_response(
        trace_id=trace_id,
        message=message,
        response=response,
        source_documents=source_documents
    )
    logger.info(f"Response score: {evaluation_scores['overall']:.2f}")
```

Key Metrics:
- **Relevance**: How well the response addresses the query (0.0-1.0)
- **Helpfulness**: How helpful and actionable the response is (0.0-1.0)
- **Accuracy**: Factual correctness based on source documents (0.0-1.0)
- **Overall**: Combined quality score (0.0-1.0)

To integrate evaluations into the Lambda function, run:

```bash
cd infras/core
python integrate_evaluations.py
```

## 3. Load Testing with Observability

The `load_test_with_langfuse.py` script enables load testing while tracking performance in Langfuse:

```bash
python load_test_with_langfuse.py \
  --endpoint https://your-api-endpoint.execute-api.us-east-1.amazonaws.com \
  --kb-queries 50 \
  --chat-messages 30 \
  --customer-status 20 \
  --concurrency 8
```

Features:
- Concurrent request handling
- Diverse test data across tenants
- Performance metrics (latency, success rate)
- Integration with Langfuse for deep observability
- Custom request headers for tracing

## 4. Automated Reporting

The `langfuse_automated_report.py` script generates PDF reports from Langfuse data:

```bash
python langfuse_automated_report.py \
  --public-key YOUR_LANGFUSE_PUBLIC_KEY \
  --secret-key YOUR_LANGFUSE_SECRET_KEY \
  --days 30 \
  --output-dir langfuse_reports
```

Report Contents:
- Usage summary statistics
- Charts of trace distribution by tenant
- Model usage breakdown
- Quality scores by metric type
- Performance trends over time

## Integration with Core Lambda Function

These monitoring features integrate seamlessly with the core Lambda function through:

1. The `langfuse_integration.py` module for tracing operations
2. The `langfuse_evaluations.py` module for quality monitoring
3. Request headers in API calls for cross-component tracing

## Testing Diverse Scenarios

The `test_langfuse_integration.sh` script includes diverse test cases:

- **Knowledge Base Queries**:
  - Implementation status queries
  - Success metrics inquiries
  - Next steps and roadmap questions
  - Digital transformation objectives
  - Stakeholder identification
  - Timeline and scheduling inquiries

- **Chat Interactions**:
  - Implementation progress conversations
  - Success metrics discussions
  - Risk assessment conversations
  - Stakeholder role clarifications
  - Timeline and planning discussions

- **Customer Status Queries**:
  - Full customer list retrieval
  - Specific customer status inquiries
  - Milestone tracking
  - Implementation stage verification

## Setup Instructions

1. **Install dependencies**:
```bash
pip install langfuse matplotlib pandas fpdf tqdm requests
```

2. **Get Langfuse API keys**:
   - Sign up at https://cloud.langfuse.com
   - Navigate to Settings > API Keys
   - Copy your public and secret keys

3. **Set environment variables**:
```bash
export LANGFUSE_PUBLIC_KEY=pk_your_public_key
export LANGFUSE_SECRET_KEY=sk_your_secret_key
```

4. **Deploy Lambda with Langfuse integration**:
```bash
cd infras/core
./deploy_with_langfuse.sh
```

5. **Run diverse tests**:
```bash
./test_langfuse_integration.sh
```

## Best Practices

1. **Real-time Monitoring**: Keep the dashboard open during development and testing

2. **Regular Reports**: Schedule automated reports to track trends over time

3. **Load Testing**: Run load tests before major releases or infrastructure changes

4. **Evaluation Thresholds**: Set quality thresholds for production alerts (e.g., if relevance drops below 0.7)

5. **Tracing Context**: Always pass trace IDs between components for end-to-end visibility

## Future Enhancements

1. **User Feedback Loop**: Integrate user feedback with traces for training data

2. **A/B Testing**: Compare different prompts and model configurations

3. **Anomaly Detection**: Automated alerting on unusual patterns

4. **Cost Optimization**: Track token usage and optimize for cost efficiency

5. **Custom Model Evaluations**: Develop tenant-specific evaluation metrics

## Conclusion

These enhanced Langfuse monitoring tools provide comprehensive observability into Cloudable.AI's LLM operations. By integrating quality evaluation, load testing, and automated reporting, you gain deeper insights into performance, reliability, and user experience.
