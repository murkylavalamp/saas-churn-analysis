-- =============================================================================
-- Project:  SaaS Customer Health & Churn Analysis
-- Script:   03_churn_cohort_analysis.sql
-- Purpose:  Deep-dive churn analysis by segment and tenure cohort
--           This is the SQL that would impress a hiring manager.
-- Author:   Simone D'Angelo
-- Date:     2026-05-27
-- =============================================================================

SET search_path = saas_churn;

-- =============================================================================
-- SECTION 1: Churn Rate by Key Dimensions
-- These are the first questions every CS/product team asks
-- =============================================================================

-- 1A: Churn by Contract Type (usually the biggest driver)
SELECT
    contract,
    COUNT(*)                            AS total_customers,
    SUM(churn_flag)                     AS churned,
    ROUND(AVG(churn_flag) * 100, 1)     AS churn_rate_pct,
    ROUND(AVG(tenure), 1)               AS avg_tenure_months,
    ROUND(AVG(monthly_charges), 2)      AS avg_monthly_charges
FROM customers
GROUP BY contract
ORDER BY churn_rate_pct DESC;


-- 1B: Churn by Internet Service Type
SELECT
    internet_service,
    COUNT(*)                            AS total_customers,
    SUM(churn_flag)                     AS churned,
    ROUND(AVG(churn_flag) * 100, 1)     AS churn_rate_pct,
    ROUND(AVG(monthly_charges), 2)      AS avg_monthly_charges
FROM customers
GROUP BY internet_service
ORDER BY churn_rate_pct DESC;


-- 1C: Churn by Payment Method (auto-pay vs manual)
SELECT
    payment_method,
    is_autopay,
    COUNT(*)                            AS total_customers,
    SUM(churn_flag)                     AS churned,
    ROUND(AVG(churn_flag) * 100, 1)     AS churn_rate_pct
FROM customers
GROUP BY payment_method, is_autopay
ORDER BY churn_rate_pct DESC;


-- 1D: Churn by Tenure Bucket (lifecycle stage)
SELECT
    tenure_bucket,
    COUNT(*)                            AS total_customers,
    SUM(churn_flag)                     AS churned,
    ROUND(AVG(churn_flag) * 100, 1)     AS churn_rate_pct,
    ROUND(AVG(monthly_charges), 2)      AS avg_monthly_charges
FROM customers
GROUP BY tenure_bucket
ORDER BY
    CASE tenure_bucket
        WHEN '0-12 months'  THEN 1
        WHEN '13-24 months' THEN 2
        WHEN '25-48 months' THEN 3
        WHEN '49-72 months' THEN 4
    END;


-- 1E: Churn by Number of Add-on Services
-- Hypothesis: more services = more sticky = less churn
SELECT
    num_services,
    COUNT(*)                            AS total_customers,
    SUM(churn_flag)                     AS churned,
    ROUND(AVG(churn_flag) * 100, 1)     AS churn_rate_pct,
    ROUND(AVG(monthly_charges), 2)      AS avg_monthly_charges
FROM customers
GROUP BY num_services
ORDER BY num_services;


-- =============================================================================
-- SECTION 2: Multi-Dimensional Churn Segmentation
-- Identify highest-risk customer clusters
-- =============================================================================

-- 2A: Cross-tab — Contract × Internet Service
--     Reveals which specific combination drives most churn
SELECT
    contract,
    internet_service,
    COUNT(*)                            AS total,
    SUM(churn_flag)                     AS churned,
    ROUND(AVG(churn_flag) * 100, 1)     AS churn_rate_pct,
    ROUND(AVG(monthly_charges), 2)      AS avg_charges
FROM customers
GROUP BY contract, internet_service
ORDER BY churn_rate_pct DESC;


-- 2B: High-Value Churners (above-median revenue, churned)
--     These are the accounts that hurt the most when lost
WITH median_charge AS (
    SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY monthly_charges) AS median_val
    FROM customers
)
SELECT
    COUNT(*)                            AS high_value_churners,
    ROUND(AVG(monthly_charges), 2)      AS avg_monthly_charges,
    ROUND(SUM(monthly_charges), 0)      AS total_monthly_revenue_lost,
    ROUND(AVG(tenure), 1)               AS avg_tenure_months,
    MODE() WITHIN GROUP (ORDER BY contract) AS most_common_contract,
    MODE() WITHIN GROUP (ORDER BY payment_method) AS most_common_payment
FROM customers, median_charge
WHERE churn_flag = 1
  AND monthly_charges > median_val;


-- 2C: The "Ticking Time Bombs" — Active customers with churn-like profile
--     Month-to-month + Fiber + Electronic check + No tech support + < 12 months tenure
SELECT
    customer_id,
    tenure,
    monthly_charges,
    internet_service,
    contract,
    payment_method,
    has_tech_support,
    num_services
FROM customers
WHERE churn_flag = 0  -- Still active!
  AND contract = 'Month-to-month'
  AND internet_service = 'Fiber optic'
  AND payment_method = 'Electronic check'
  AND has_tech_support = FALSE
  AND tenure < 12
ORDER BY monthly_charges DESC
LIMIT 50;


-- =============================================================================
-- SECTION 3: Cohort Retention Analysis
-- Using window functions — this is what separates junior from senior analysts
-- =============================================================================

-- 3A: Monthly churn rate simulation by tenure month
--     (Survival analysis proxy — how does churn rate change over a customer's life?)
WITH tenure_churn AS (
    SELECT
        tenure                                              AS months_active,
        COUNT(*)                                            AS total_at_tenure,
        SUM(churn_flag)                                     AS churned_at_tenure,
        ROUND(AVG(churn_flag) * 100, 2)                     AS churn_rate_pct,
        -- Running survival rate (all customers who made it past each month)
        ROUND(
            SUM(COUNT(*)) OVER (ORDER BY tenure ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
            / SUM(COUNT(*)) OVER () * 100, 2
        )                                                   AS pct_customers_surviving
    FROM customers
    GROUP BY tenure
)
SELECT
    months_active,
    total_at_tenure,
    churned_at_tenure,
    churn_rate_pct,
    pct_customers_surviving
FROM tenure_churn
ORDER BY months_active;


-- 3B: Retention by Tenure Cohort × Contract Type
--     Shows which contract types retain well across lifecycle stages
SELECT
    tenure_bucket,
    contract,
    COUNT(*)                            AS total_customers,
    SUM(churn_flag)                     AS churned,
    ROUND(AVG(churn_flag) * 100, 1)     AS churn_rate_pct,
    -- % of all churn that comes from this cohort
    ROUND(
        SUM(churn_flag) * 100.0 / SUM(SUM(churn_flag)) OVER (),
        1
    )                                   AS pct_of_total_churn
FROM customers
GROUP BY tenure_bucket, contract
ORDER BY churn_rate_pct DESC;


-- 3C: Rank customers within contract type by churn risk factors
--     Uses ROW_NUMBER + multiple risk signals
WITH risk_ranked AS (
    SELECT
        customer_id,
        contract,
        tenure,
        monthly_charges,
        num_services,
        is_autopay,
        has_tech_support,
        churn_flag,
        -- Rank within contract group: highest charges, fewest services, shortest tenure = highest risk
        ROW_NUMBER() OVER (
            PARTITION BY contract
            ORDER BY
                monthly_charges DESC,
                num_services ASC,
                tenure ASC
        )                               AS risk_rank_in_contract,
        COUNT(*) OVER (PARTITION BY contract) AS contract_group_size
    FROM customers
    WHERE churn_flag = 0  -- Active customers only
)
SELECT *
FROM risk_ranked
WHERE risk_rank_in_contract <= 10
ORDER BY contract, risk_rank_in_contract;
