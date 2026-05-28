-- =============================================================================
-- Project:  SaaS Customer Health & Churn Analysis
-- Script:   01_schema_setup.sql
-- Purpose:  Create the database schema and load raw customer data
-- Author:   Simone D'Angelo
-- Date:     2026-05-27
-- =============================================================================

-- Drop and recreate schema for clean setup
DROP SCHEMA IF EXISTS saas_churn CASCADE;
CREATE SCHEMA saas_churn;
SET search_path = saas_churn;

-- =============================================================================
-- TABLE: raw_customers
-- Mirrors the Kaggle CSV exactly — no transformations applied here
-- =============================================================================
DROP TABLE IF EXISTS raw_customers;

CREATE TABLE raw_customers (
    customer_id        VARCHAR(20)   PRIMARY KEY,
    gender             VARCHAR(10),
    senior_citizen     INTEGER,          -- 0 or 1
    partner            VARCHAR(5),
    dependents         VARCHAR(5),
    tenure             INTEGER,          -- months
    phone_service      VARCHAR(5),
    multiple_lines     VARCHAR(25),
    internet_service   VARCHAR(20),
    online_security    VARCHAR(25),
    online_backup      VARCHAR(25),
    device_protection  VARCHAR(25),
    tech_support       VARCHAR(25),
    streaming_tv       VARCHAR(25),
    streaming_movies   VARCHAR(25),
    contract           VARCHAR(20),
    paperless_billing  VARCHAR(5),
    payment_method     VARCHAR(35),
    monthly_charges    NUMERIC(8,2),
    total_charges      VARCHAR(10),      -- raw string — cleaned in next step
    churn              VARCHAR(5)
);

-- =============================================================================
-- !! STOP HERE — load the CSV before continuing !!
--
-- Run the following in psql (from the project root directory):
--
--   \COPY saas_churn.raw_customers
--     FROM 'data/raw/WA_Fn-UseC_-Telco-Customer-Churn.csv'
--     WITH (FORMAT csv, HEADER true, DELIMITER ',');
--
-- Verify the load succeeded:
--   SELECT COUNT(*) FROM saas_churn.raw_customers;  -- expected: 7043
--
-- Then continue running the remainder of this script.
-- =============================================================================

-- =============================================================================
-- TABLE: customers
-- Cleaned, typed, and enriched version of raw_customers
-- This is the primary analysis table
-- =============================================================================
DROP TABLE IF EXISTS customers;

CREATE TABLE customers AS
SELECT
    customer_id,
    gender,
    senior_citizen::BOOLEAN                                      AS is_senior,
    CASE WHEN partner = 'Yes' THEN TRUE ELSE FALSE END           AS has_partner,
    CASE WHEN dependents = 'Yes' THEN TRUE ELSE FALSE END        AS has_dependents,
    tenure,

    -- Service flags (normalized to boolean)
    CASE WHEN phone_service = 'Yes' THEN TRUE ELSE FALSE END     AS has_phone,
    CASE WHEN multiple_lines = 'Yes' THEN TRUE ELSE FALSE END    AS has_multi_lines,
    internet_service,
    CASE WHEN online_security = 'Yes' THEN TRUE ELSE FALSE END   AS has_online_security,
    CASE WHEN online_backup = 'Yes' THEN TRUE ELSE FALSE END     AS has_online_backup,
    CASE WHEN device_protection = 'Yes' THEN TRUE ELSE FALSE END AS has_device_protection,
    CASE WHEN tech_support = 'Yes' THEN TRUE ELSE FALSE END      AS has_tech_support,
    CASE WHEN streaming_tv = 'Yes' THEN TRUE ELSE FALSE END      AS has_streaming_tv,
    CASE WHEN streaming_movies = 'Yes' THEN TRUE ELSE FALSE END  AS has_streaming_movies,

    -- Contract and billing
    contract,
    CASE WHEN paperless_billing = 'Yes' THEN TRUE ELSE FALSE END AS paperless_billing,
    payment_method,
    monthly_charges,

    -- Clean TotalCharges: blank strings (new customers) → use MonthlyCharges
    CASE
        WHEN total_charges = '' OR total_charges IS NULL
        THEN monthly_charges
        ELSE total_charges::NUMERIC(10,2)
    END AS total_charges,

    -- Target variable
    CASE WHEN churn = 'Yes' THEN 1 ELSE 0 END AS churn_flag,

    -- Derived features
    -- Count of active add-on services (max 6)
    (
        CASE WHEN online_security = 'Yes' THEN 1 ELSE 0 END +
        CASE WHEN online_backup = 'Yes' THEN 1 ELSE 0 END +
        CASE WHEN device_protection = 'Yes' THEN 1 ELSE 0 END +
        CASE WHEN tech_support = 'Yes' THEN 1 ELSE 0 END +
        CASE WHEN streaming_tv = 'Yes' THEN 1 ELSE 0 END +
        CASE WHEN streaming_movies = 'Yes' THEN 1 ELSE 0 END
    ) AS num_services,

    -- Tenure bucketed into cohort bands
    CASE
        WHEN tenure BETWEEN 0  AND 12 THEN '0-12 months'
        WHEN tenure BETWEEN 13 AND 24 THEN '13-24 months'
        WHEN tenure BETWEEN 25 AND 48 THEN '25-48 months'
        WHEN tenure BETWEEN 49 AND 72 THEN '49-72 months'
    END AS tenure_bucket,

    -- Auto-pay flag (lower churn proxy)
    CASE
        WHEN payment_method IN ('Bank transfer (automatic)', 'Credit card (automatic)')
        THEN TRUE ELSE FALSE
    END AS is_autopay

FROM raw_customers;

-- Add primary key
ALTER TABLE customers ADD PRIMARY KEY (customer_id);

-- Add index on churn for fast filtering
CREATE INDEX idx_customers_churn ON customers(churn_flag);
CREATE INDEX idx_customers_contract ON customers(contract);
CREATE INDEX idx_customers_tenure ON customers(tenure);

-- Quick sanity check
SELECT
    COUNT(*)                                    AS total_customers,
    SUM(churn_flag)                             AS total_churned,
    ROUND(AVG(churn_flag) * 100, 2)             AS churn_rate_pct,
    ROUND(AVG(monthly_charges), 2)              AS avg_monthly_charge,
    ROUND(AVG(tenure), 1)                       AS avg_tenure_months
FROM customers;
