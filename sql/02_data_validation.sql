-- =============================================================================
-- Project:  SaaS Customer Health & Churn Analysis
-- Script:   02_data_validation.sql
-- Purpose:  Data quality checks before analysis
--           In a real company, these would be run in dbt tests or Great Expectations
-- Author:   Simone D'Angelo
-- Date:     2026-05-27
-- =============================================================================

SET search_path = saas_churn;

-- =============================================================================
-- CHECK 1: Row counts and basic completeness
-- =============================================================================
SELECT
    'Total rows'            AS check_name,
    COUNT(*)::TEXT          AS result,
    'Expected ~7043'        AS note
FROM customers

UNION ALL

SELECT
    'Null customer_id',
    COUNT(*)::TEXT,
    'Expected 0'
FROM customers
WHERE customer_id IS NULL

UNION ALL

SELECT
    'Null monthly_charges',
    COUNT(*)::TEXT,
    'Expected 0'
FROM customers
WHERE monthly_charges IS NULL

UNION ALL

SELECT
    'Null tenure',
    COUNT(*)::TEXT,
    'Expected 0'
FROM customers
WHERE tenure IS NULL

UNION ALL

SELECT
    'Null churn_flag',
    COUNT(*)::TEXT,
    'Expected 0'
FROM customers
WHERE churn_flag IS NULL;

-- =============================================================================
-- CHECK 2: Duplicate customer IDs
-- =============================================================================
SELECT
    'Duplicate customer IDs' AS check_name,
    COUNT(*) - COUNT(DISTINCT customer_id) AS duplicate_count,
    'Expected 0' AS note
FROM customers;

-- =============================================================================
-- CHECK 3: Value distributions — catch unexpected categories
-- =============================================================================

-- Contract types
SELECT 'Contract types' AS field, contract AS value, COUNT(*) AS count
FROM customers
GROUP BY contract
ORDER BY count DESC;

-- Internet service
SELECT 'Internet service' AS field, internet_service AS value, COUNT(*) AS count
FROM customers
GROUP BY internet_service
ORDER BY count DESC;

-- Payment methods
SELECT 'Payment methods' AS field, payment_method AS value, COUNT(*) AS count
FROM customers
GROUP BY payment_method
ORDER BY count DESC;

-- Gender
SELECT 'Gender' AS field, gender AS value, COUNT(*) AS count
FROM customers
GROUP BY gender
ORDER BY count DESC;

-- =============================================================================
-- CHECK 4: Numeric range validation
-- =============================================================================
SELECT
    MIN(monthly_charges)   AS min_monthly,
    MAX(monthly_charges)   AS max_monthly,
    ROUND(AVG(monthly_charges), 2) AS avg_monthly,
    MIN(total_charges)     AS min_total,
    MAX(total_charges)     AS max_total,
    MIN(tenure)            AS min_tenure,
    MAX(tenure)            AS max_tenure
FROM customers;

-- Flag suspicious records: zero charges but active customer
SELECT COUNT(*) AS suspicious_zero_charge_customers
FROM customers
WHERE monthly_charges = 0 AND tenure > 0;

-- =============================================================================
-- CHECK 5: Business logic validation
-- Customers with No internet service shouldn't have internet add-ons
-- =============================================================================
SELECT
    'Internet add-ons without internet' AS check_name,
    COUNT(*) AS count
FROM customers
WHERE internet_service = 'No'
  AND (has_online_security OR has_online_backup OR has_device_protection
       OR has_tech_support OR has_streaming_tv OR has_streaming_movies);

-- =============================================================================
-- CHECK 6: Churn rate sanity check by major segment
-- =============================================================================
SELECT
    contract,
    COUNT(*)                                AS total,
    SUM(churn_flag)                         AS churned,
    ROUND(AVG(churn_flag) * 100, 1)         AS churn_rate_pct
FROM customers
GROUP BY contract
ORDER BY churn_rate_pct DESC;

-- =============================================================================
-- SUMMARY REPORT
-- =============================================================================
SELECT
    COUNT(*)                                              AS total_customers,
    SUM(churn_flag)                                       AS churned_customers,
    COUNT(*) - SUM(churn_flag)                            AS retained_customers,
    ROUND(AVG(churn_flag) * 100, 2)                       AS overall_churn_pct,
    ROUND(SUM(monthly_charges), 0)                        AS total_mrr,
    ROUND(SUM(CASE WHEN churn_flag = 1 THEN monthly_charges END), 0) AS mrr_lost_to_churn,
    ROUND(
        SUM(CASE WHEN churn_flag = 1 THEN monthly_charges END)
        / SUM(monthly_charges) * 100, 2
    )                                                     AS revenue_churn_pct
FROM customers;
