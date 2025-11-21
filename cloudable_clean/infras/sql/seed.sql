INSERT INTO tenants(tenant_id, name) VALUES
('t001','acme'), ('t002','globex')
ON CONFLICT (tenant_id) DO NOTHING;

INSERT INTO customers(tenant_id, customer_id, name, primary_contact) VALUES
('t001','acme-001','ACME Motors','alice@acme.com'),
('t001','acme-002','ACME Retail','bob@acme.com'),
('t002','globex-001','Globex Pharma','eva@globex.com');

INSERT INTO journeys(tenant_id, customer_id, stage, tasks_completed) VALUES
('t001','acme-001','Enablement',5),
('t001','acme-002','Assessment',2),
('t002','globex-001','Discovery',1);

INSERT INTO assessments(tenant_id, customer_id, assessed_at, q1,q2,q3,q4,q5,q6,q7,q8,q9,q10) VALUES
('t001','acme-001', now() - interval '5 days',
 'Strong cloud landing zone','Gaps in CI/CD','Needs cost guardrails','Basic monitoring','No drift control',
 'KMS everywhere','Private subnets','No WAF', 'No SSO', 'Limited IAM boundaries'),
('t001','acme-002', now() - interval '2 days',
 'No IaC','Manual deploys','No central logging','Weak tagging','Unencrypted S3',
 'No backup SOP','No DR plan','Flat VPCs','Open SGs','No budgets'),
('t002','globex-001', now() - interval '1 day',
 'Mature DevOps','Well-tagged','Encrypted by default','SSO enforced','GuardDuty enabled',
 'WAF on ALB','Data classification','Lineage in place','SageMaker pipelines','CloudTrail org trails');

INSERT INTO kb_items(tenant_id, doc_id, s3_uri, title, tags) VALUES
('t001','deploy_guide_v1','s3://cloudable-kb-dev-acme/deploy/guide_v1.pdf','Deployment Guide v1', ARRAY['deployment','guide']),
('t001','sec_policy','s3://cloudable-kb-dev-acme/security/policy.pdf','Security Policy', ARRAY['security']),
('t002','kb_overview','s3://cloudable-kb-dev-globex/overview.pdf','KB Overview', ARRAY['overview']);
