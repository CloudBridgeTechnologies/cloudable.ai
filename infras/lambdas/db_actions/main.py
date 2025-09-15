import json, os, boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

rds = boto3.client("rds-data")
CLUSTER_ARN = os.environ["DB_CLUSTER_ARN"]
SECRET_ARN  = os.environ["DB_SECRET_ARN"]
DB_NAME     = os.environ["DB_NAME"]

def q(sql, params):
    logger.info(f"Executing SQL: {sql} with params: {params}")
    return rds.execute_statement(
        resourceArn=CLUSTER_ARN,
        secretArn=SECRET_ARN,
        database=DB_NAME,
        sql=sql,
        parameters=params,
        includeResultMetadata=True
    )

def handler(event, context):
    logger.info(f"Received event: {json.dumps(event)}")
    
    # Bedrock Agent (Lambda executor) can send parameters either in queryStringParameters
    # or in requestBody (as a JSON string or object). It also includes inputText which
    # we can use to infer intent when a single action operation is defined.
    # Determine op from functionSchema invocation or OpenAPI
    op   = event.get("operation") or event.get("apiPath", "") or ""
    qp   = event.get("queryStringParameters") or {}

    # Parse requestBody if present (support Bedrock action group shapes)
    body = {}
    body_raw = event.get("requestBody")
    try:
        if isinstance(body_raw, str):
            body = json.loads(body_raw)
        elif isinstance(body_raw, dict):
            # Possible shape: { content: { "application/json": { body: "{...}" or {...} } } }
            content = body_raw.get("content")
            if isinstance(content, dict):
                app_json = content.get("application/json") or content.get("application\\/json")
                if isinstance(app_json, dict):
                    inner = app_json.get("body")
                    if isinstance(inner, str):
                        body = json.loads(inner)
                    elif isinstance(inner, dict):
                        body = inner
                    # Handle properties array format from Bedrock Agent
                    elif "properties" in app_json:
                        for prop in app_json.get("properties", []):
                            if isinstance(prop, dict) and "name" in prop and "value" in prop:
                                body[prop["name"]] = prop["value"]
            if not body:
                body = body_raw
    except Exception:
        body = {}

    # Also support parameters array/dict shapes
    param_list = event.get("parameters") or []
    if isinstance(param_list, dict):
        # functionSchema may send parameters as a dict
        body.setdefault("tenant_id", param_list.get("tenant_id"))
        body.setdefault("customer_id", param_list.get("customer_id"))
    elif isinstance(param_list, list):
        for p in param_list:
            try:
                name = p.get("name")
                value = p.get("value")
                if name == "tenant_id" and value and not body.get("tenant_id"):
                    body["tenant_id"] = value
                if name == "customer_id" and value and not body.get("customer_id"):
                    body["customer_id"] = value
            except Exception:
                pass

    tenant = qp.get("tenant_id") or body.get("tenant_id")
    customer = qp.get("customer_id") or body.get("customer_id")
    
    logger.info(f"Extracted tenant: {tenant}, customer: {customer}, operation: {op}")

    if not tenant or not customer:
        logger.error(f"Missing parameters - tenant: {tenant}, customer: {customer}")
        return _resp(event, 400, {"error":"tenant_id and customer_id required"})

    # Determine intent. Prefer explicit operation path, fallback to inputText heuristics.
    input_text = (event.get("inputText") or "").lower()

    if "journey_status" in op or op == "get_journey_status" or ("journey" in input_text and "status" in input_text):
        sql = """
        SELECT stage, tasks_completed, last_update
        FROM journeys
        WHERE tenant_id = :tenant_id AND customer_id = :customer_id
        """
        params = [{"name":"tenant_id","value":{"stringValue":tenant}},
                  {"name":"customer_id","value":{"stringValue":customer}}]
        res = q(sql, params)
        logger.info(f"Journey query result: {res}")
        rows = _rows(res)
        logger.info(f"Journey parsed rows: {rows}")
        j = rows[0] if rows else None
        if j:
            result_text = f"Journey stage: {j.get('stage')}, tasks_completed: {j.get('tasks_completed')}, last_update: {j.get('last_update')}"
        else:
            result_text = "No journey record found"
        return _resp(event, 200, {"result": result_text})

    if "assessments_summary" in op or op == "get_assessments_summary" or ("assessment" in input_text and "summary" in input_text):
        sql = """
        SELECT assessed_at, q1, q2, q3, q4, q5
        FROM assessments
        WHERE tenant_id = :tenant_id AND customer_id = :customer_id
        """
        params = [{"name":"tenant_id","value":{"stringValue":tenant}},
                  {"name":"customer_id","value":{"stringValue":customer}}]
        res = q(sql, params)
        rows = _rows(res)
        # trivial summarization on Lambda (pre-LLM condensation)
        if rows:
            r = rows[0]
            qs = [r.get(f"q{i}") for i in range(1,6)]
            result_text = f"Assessment at {r.get('assessed_at')}: " + "; ".join([q for q in qs if q])
        else:
            result_text = "No assessment record found"
        return _resp(event, 200, {"result": result_text})

    return _resp(event, 400, {"error":"unknown operation"})

def _rows(res):
    cols = [c["name"] for c in res["columnMetadata"]]
    out = []
    for r in res.get("records", []):
        obj = {}
        for c, v in zip(cols, r):
            key = list(v.keys())[0]
            obj[c] = v[key]
        out.append(obj)
    return out

def _resp(event, status_code, obj):
    return {
        "messageVersion": "1.0",
        "response": {
            "actionGroup": event.get("actionGroup", "rds_read"),
            "apiPath": event.get("apiPath", "/invoke"),
            "httpMethod": event.get("httpMethod", "POST"),
            "httpStatusCode": status_code,
            "responseBody": {
                "application/json": {
                    "body": json.dumps(obj)
                }
            }
        }
    }
