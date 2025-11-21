-- SQL script to create customer status tracking tables with tenant isolation
-- This script creates tenant-specific tables to store customer implementation status

-- Create schema for customer status tracking if not exists
CREATE SCHEMA IF NOT EXISTS customer_status;

-- Function to create tenant-specific customer status tables
CREATE OR REPLACE FUNCTION customer_status.create_tenant_tables(tenant_id TEXT) 
RETURNS VOID AS $$
DECLARE
    implementation_stages_table TEXT := 'customer_status.implementation_stages_' || tenant_id;
    customer_status_table TEXT := 'customer_status.customer_status_' || tenant_id;
    customer_milestones_table TEXT := 'customer_status.customer_milestones_' || tenant_id;
    status_history_table TEXT := 'customer_status.status_history_' || tenant_id;
BEGIN
    -- Create implementation stages table for this tenant
    EXECUTE format('
        CREATE TABLE IF NOT EXISTS %s (
            stage_id SERIAL PRIMARY KEY,
            stage_name TEXT NOT NULL,
            stage_description TEXT,
            typical_duration_days INTEGER,
            stage_order INTEGER NOT NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );
    ', implementation_stages_table);
    
    -- Create customer status table for this tenant
    EXECUTE format('
        CREATE TABLE IF NOT EXISTS %s (
            customer_id UUID PRIMARY KEY,
            customer_name TEXT NOT NULL,
            current_stage_id INTEGER NOT NULL,
            implementation_start_date DATE NOT NULL,
            projected_completion_date DATE,
            actual_completion_date DATE,
            status TEXT NOT NULL DEFAULT ''active'',
            health_status TEXT NOT NULL DEFAULT ''on_track'',
            progress_percentage NUMERIC(5,2) DEFAULT 0.0,
            last_updated_by TEXT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT fk_current_stage FOREIGN KEY (current_stage_id) REFERENCES %s (stage_id)
        );
    ', customer_status_table, implementation_stages_table);
    
    -- Create customer milestones table for this tenant
    EXECUTE format('
        CREATE TABLE IF NOT EXISTS %s (
            milestone_id SERIAL PRIMARY KEY,
            customer_id UUID NOT NULL,
            milestone_name TEXT NOT NULL,
            milestone_description TEXT,
            planned_date DATE,
            actual_date DATE,
            status TEXT NOT NULL DEFAULT ''pending'',
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT fk_customer FOREIGN KEY (customer_id) REFERENCES %s (customer_id)
        );
    ', customer_milestones_table, customer_status_table);
    
    -- Create status history table for this tenant
    EXECUTE format('
        CREATE TABLE IF NOT EXISTS %s (
            history_id SERIAL PRIMARY KEY,
            customer_id UUID NOT NULL,
            previous_stage_id INTEGER,
            new_stage_id INTEGER NOT NULL,
            change_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            changed_by TEXT,
            notes TEXT,
            CONSTRAINT fk_customer_history FOREIGN KEY (customer_id) REFERENCES %s (customer_id),
            CONSTRAINT fk_previous_stage FOREIGN KEY (previous_stage_id) REFERENCES %s (stage_id),
            CONSTRAINT fk_new_stage FOREIGN KEY (new_stage_id) REFERENCES %s (stage_id)
        );
    ', status_history_table, customer_status_table, implementation_stages_table, implementation_stages_table);

    -- Add indexes for better query performance
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%s_customer_id ON %s (customer_id);', 
        substring(customer_milestones_table from 17), customer_milestones_table);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%s_customer_stage ON %s (customer_id, current_stage_id);', 
        substring(customer_status_table from 17), customer_status_table);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%s_health_status ON %s (health_status);', 
        substring(customer_status_table from 17), customer_status_table);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%s_customer_id ON %s (customer_id);', 
        substring(status_history_table from 17), status_history_table);
    
END;
$$ LANGUAGE plpgsql;

-- Function to seed sample implementation stages for a tenant
CREATE OR REPLACE FUNCTION customer_status.seed_implementation_stages(tenant_id TEXT) 
RETURNS VOID AS $$
DECLARE
    implementation_stages_table TEXT := 'customer_status.implementation_stages_' || tenant_id;
BEGIN
    -- Clear existing stages
    EXECUTE format('TRUNCATE TABLE %s RESTART IDENTITY CASCADE;', implementation_stages_table);
    
    -- Insert standard implementation stages
    EXECUTE format('
        INSERT INTO %s (stage_name, stage_description, typical_duration_days, stage_order) VALUES
        (''Discovery'', ''Initial assessment and requirements gathering'', 30, 1),
        (''Planning'', ''Implementation planning and resource allocation'', 45, 2),
        (''Implementation'', ''Core system deployment and configuration'', 60, 3),
        (''Integration'', ''Integration with existing systems'', 30, 4),
        (''Testing'', ''User acceptance testing and quality assurance'', 15, 5),
        (''Training'', ''End-user training and documentation'', 15, 6),
        (''Go-Live'', ''Production deployment'', 5, 7),
        (''Post-Implementation'', ''Support and optimization'', 30, 8);
    ', implementation_stages_table);
END;
$$ LANGUAGE plpgsql;

-- Function to insert a sample customer for testing
CREATE OR REPLACE FUNCTION customer_status.insert_sample_customer(
    tenant_id TEXT,
    p_customer_id UUID,
    p_customer_name TEXT,
    p_stage_id INTEGER,
    p_start_date DATE,
    p_projected_date DATE,
    p_health_status TEXT,
    p_progress_percentage NUMERIC(5,2)
) 
RETURNS VOID AS $$
DECLARE
    customer_status_table TEXT := 'customer_status.customer_status_' || tenant_id;
BEGIN
    -- Insert or update the customer
    EXECUTE format('
        INSERT INTO %s (
            customer_id, 
            customer_name, 
            current_stage_id, 
            implementation_start_date, 
            projected_completion_date,
            health_status,
            progress_percentage
        ) VALUES (
            $1, $2, $3, $4, $5, $6, $7
        )
        ON CONFLICT (customer_id) 
        DO UPDATE SET
            customer_name = $2,
            current_stage_id = $3, 
            implementation_start_date = $4,
            projected_completion_date = $5,
            health_status = $6,
            progress_percentage = $7,
            updated_at = NOW();
    ', customer_status_table)
    USING 
        p_customer_id, 
        p_customer_name, 
        p_stage_id, 
        p_start_date, 
        p_projected_date,
        p_health_status,
        p_progress_percentage;
END;
$$ LANGUAGE plpgsql;

-- Function to add a milestone for a customer
CREATE OR REPLACE FUNCTION customer_status.add_milestone(
    tenant_id TEXT,
    p_customer_id UUID,
    p_milestone_name TEXT,
    p_milestone_description TEXT,
    p_planned_date DATE,
    p_status TEXT
) 
RETURNS VOID AS $$
DECLARE
    customer_milestones_table TEXT := 'customer_status.customer_milestones_' || tenant_id;
BEGIN
    -- Insert the milestone
    EXECUTE format('
        INSERT INTO %s (
            customer_id,
            milestone_name,
            milestone_description,
            planned_date,
            status
        ) VALUES (
            $1, $2, $3, $4, $5
        );
    ', customer_milestones_table)
    USING 
        p_customer_id, 
        p_milestone_name,
        p_milestone_description,
        p_planned_date,
        p_status;
END;
$$ LANGUAGE plpgsql;

-- Create a view-generation function for consolidated customer status
CREATE OR REPLACE FUNCTION customer_status.create_status_view(tenant_id TEXT)
RETURNS TEXT AS $$
DECLARE
    view_name TEXT := 'customer_status.customer_status_view_' || tenant_id;
    implementation_stages_table TEXT := 'customer_status.implementation_stages_' || tenant_id;
    customer_status_table TEXT := 'customer_status.customer_status_' || tenant_id;
    customer_milestones_table TEXT := 'customer_status.customer_milestones_' || tenant_id;
BEGIN
    -- Create a view that joins customer status with their current stage
    EXECUTE format('
        CREATE OR REPLACE VIEW %s AS
        SELECT 
            cs.customer_id,
            cs.customer_name,
            cs.status,
            cs.health_status,
            cs.progress_percentage,
            cs.implementation_start_date,
            cs.projected_completion_date,
            cs.actual_completion_date,
            stg.stage_id,
            stg.stage_name,
            stg.stage_description,
            stg.stage_order,
            (SELECT COUNT(*) FROM %s WHERE customer_id = cs.customer_id) AS milestone_count,
            (SELECT COUNT(*) FROM %s WHERE customer_id = cs.customer_id AND status = ''completed'') AS completed_milestones,
            cs.updated_at
        FROM 
            %s cs
        JOIN 
            %s stg ON cs.current_stage_id = stg.stage_id;
    ', view_name, customer_milestones_table, customer_milestones_table, customer_status_table, implementation_stages_table);
    
    RETURN view_name;
END;
$$ LANGUAGE plpgsql;
