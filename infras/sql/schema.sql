CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE tenants (
  tenant_id   text PRIMARY KEY,
  name        text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE customers (
  tenant_id   text NOT NULL REFERENCES tenants(tenant_id),
  customer_id text NOT NULL,
  name        text NOT NULL,
  primary_contact text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, customer_id)
);

CREATE TABLE journeys (
  tenant_id        text NOT NULL,
  customer_id      text NOT NULL,
  stage            text NOT NULL CHECK (stage IN ('Discovery','Assessment','Enablement','Launch','Scale')),
  tasks_completed  int  NOT NULL DEFAULT 0,
  last_update      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, customer_id),
  FOREIGN KEY (tenant_id, customer_id) REFERENCES customers(tenant_id, customer_id)
);

-- 50 Q/A columns are often better as EAV; for speed we model 10 here, extend to q50
CREATE TABLE assessments (
  tenant_id   text NOT NULL,
  customer_id text NOT NULL,
  assessed_at timestamptz NOT NULL DEFAULT now(),
  q1  text, q2  text, q3  text, q4  text, q5  text,
  q6  text, q7  text, q8  text, q9  text, q10 text,
  PRIMARY KEY (tenant_id, customer_id, assessed_at),
  FOREIGN KEY (tenant_id, customer_id) REFERENCES customers(tenant_id, customer_id)
);

CREATE TABLE kb_items (
  tenant_id   text NOT NULL,
  doc_id      text NOT NULL,
  s3_uri      text NOT NULL,
  title       text NOT NULL,
  tags        text[],
  last_synced timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, doc_id)
);

-- Indexes for common access patterns
CREATE INDEX ix_journeys_tenant_customer ON journeys(tenant_id, customer_id);
CREATE INDEX ix_assessments_tenant_customer ON assessments(tenant_id, customer_id, assessed_at DESC);
CREATE INDEX ix_kb_items_tenant ON kb_items(tenant_id);
