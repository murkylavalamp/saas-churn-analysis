-- =============================================================================
-- Project:  SaaS Customer Health & Churn Analysis
-- Script:   04_revenue_impact.sql
-- Purpose:  Revenue churn analysis — translates churn rates into dollar impact
--           This is what gets CFO and executive attention
-- Author:   Simone D'Angelo
-- Date:     2026-05-27
-- =============================================================================

SET search_path = saas_churn;

-- =============================================================================
-- SECTION 1: Revenue Overview
-- =============================================================================

-- 1A: Total MRR, revenue churn, and ARR impact
SELECT
    -- Active base
    COUNT(*) FILTER (WHERE churn_flag = 0)                          AS active_customers,
    ROUND(SUM(monthly_charges) FILTER (WHERE churn_flag = 0), 0)    AS current_mrr,
    ROUND(SUM(monthly_charges) FILTER (WHERE churn_flag = 0) * 12, 0) AS arr_run_rate,

    -- Lost revenue
    COUNT(*) FILTER (WHERE churn_flag = 1)                          AS churned_customers,
    ROUND(SUM(monthly_charges) FILTER (WHERE churn_flag = 1), 0)    AS mrr_lost,
    ROUND(SUM(monthly_charges) FILTER (WHERE churn_flag = 1) * 12, 0) AS arr_lost_annualized,

    -- Revenue churn rate
    ROUND(
        SUM(monthly_charges) FILTER (WHERE churn_flag = 1)
        / SUM(monthly_charges) * 100, 2
    )                                                               AS revenue_churn_pct,

    -- LTV proxy: avg monthly charges × avg tenure
    ROUND(AVG(monthly_charges) * AVG(tenure), 0)                    AS avg_ltv_estimate

FROM customers;


-- 1B: MRR breakdown by contract type (where is our revenue concentrated?)
SELECT
    contract,
    churn_flag,
    COUNT(*)                                    AS customers,
    ROUND(SUM(monthly_charges), 0)              AS mrr,
    ROUND(AVG(monthly_charges), 2)              AS avg_mrr_per_customer,
    -- % of total MRR this segment represents
    ROUND(
        SUM(monthly_charges) * 100.0 / SUM(SUM(monthly_charges)) OVER (),
        1
    )                                           AS pct_of_total_mrr
FROM customers
GROUP BY contract, churn_flag
ORDER BY contract, churn_flag;


-- =============================================================================
-- SECTION 2: Revenue at Risk — Active Customers with High Churn Signals
-- =============================================================================

-- 2A: MRR at risk from high-risk active customer segments
WITH risk_segments AS (
    SELECT
        customer_id,
        monthly_charges,
        contract,
        internet_service,
        payment_method,
        has_tech_support,
        tenure,
        num_services,

        -- Simple risk scoring: count how many risk factors apply
        (
            CASE WHEN contract = 'Month-to-month' THEN 2 ELSE 0 END +
            CASE WHEN internet_service = 'Fiber optic' THEN 1 ELSE 0 END +
            CASE WHEN payment_method = 'Electronic check' THEN 1 ELSE 0 END +
            CASE WHEN has_tech_support = FALSE THEN 1 ELSE 0 END +
            CASE WHEN tenure < 12 THEN 1 ELSE 0 END +
            CASE WHEN num_services <= 1 THEN 1 ELSE 0 END
        ) AS risk_score
    FROM customers
    WHERE churn_flag = 0  -- Active customers only
)
SELECT
    CASE
        WHEN risk_score >= 5 THEN 'Critical (5-7)'
        WHEN risk_score >= 3 THEN 'High (3-4)'
        WHEN risk_score = 2  THEN 'Medium (2)'
        ELSE 'Low (0-1)'
    END                                     AS risk_tier,
    COUNT(*)                                AS customer_count,
    ROUND(SUM(monthly_charges), 0)          AS mrr_at_risk,
    ROUND(SUM(monthly_charges) * 12, 0)     AS arr_at_risk,
    ROUND(AVG(monthly_charges), 2)          AS avg_monthly_charge
FROM risk_segments
GROUP BY
    CASE
        WHEN risk_score >= 5 THEN 'Critical (5-7)'
        WHEN risk_score >= 3 THEN 'High (3-4)'
        WHEN risk_score = 2  THEN 'Medium (2)'
        ELSE 'Low (0-1)'
    END
ORDER BY arr_at_risk DESC;


-- 2B: Revenue impact of targeted retention interventions
--     "If we retained X% of critical customers, what's the dollar value?"
WITH critical_accounts AS (
    SELECT
        SUM(monthly_charges) AS critical_mrr,
        COUNT(*)             AS critical_count
    FROM customers
    WHERE churn_flag = 0
      AND contract = 'Month-to-month'
      AND internet_service = 'Fiber optic'
      AND payment_method = 'Electronic check'
      AND tenure < 12
)
SELECT
    critical_count                                          AS critical_customers,
    ROUND(critical_mrr, 0)                                  AS monthly_mrr_at_risk,
    -- Revenue saved at different retention success rates
    ROUND(critical_mrr * 0.20 * 12, 0)                      AS arr_saved_at_20pct_retention,
    ROUND(critical_mrr * 0.35 * 12, 0)                      AS arr_saved_at_35pct_retention,
    ROUND(critical_mrr * 0.50 * 12, 0)                      AS arr_saved_at_50pct_retention
FROM critical_accounts;


-- =============================================================================
-- SECTION 3: LTV and Revenue Composition
-- =============================================================================

-- 3A: LTV by contract type — which customers are actually the most valuable?
SELECT
    contract,
    COUNT(*)                                AS customers,
    ROUND(AVG(tenure), 1)                   AS avg_tenure_months,
    ROUND(AVG(monthly_charges), 2)          AS avg_monthly_charges,
    -- LTV proxy = avg charges × avg tenure
    ROUND(AVG(monthly_charges) * AVG(tenure), 0) AS avg_ltv_proxy,
    ROUND(AVG(total_charges), 0)            AS avg_actual_total_charges
FROM customers
GROUP BY contract
ORDER BY avg_ltv_proxy DESC;


-- 3B: Revenue concentration — Pareto analysis
--     Do the top 20% of customers generate 80% of revenue?
WITH ranked_customers AS (
    SELECT
        customer_id,
        monthly_charges,
        NTILE(5) OVER (ORDER BY monthly_charges DESC) AS revenue_quintile
    FROM customers
    WHERE churn_flag = 0
),
quintile_summary AS (
    SELECT
        revenue_quintile,
        COUNT(*)                            AS customers,
        ROUND(SUM(monthly_charges), 0)      AS mrr,
        ROUND(AVG(monthly_charges), 2)      AS avg_mrr
    FROM ranked_customers
    GROUP BY revenue_quintile
)
SELECT
    revenue_quintile,
    CASE revenue_quintile
        WHEN 1 THEN 'Top 20%'
        WHEN 2 THEN '20-40%'
        WHEN 3 THEN '40-60%'
        WHEN 4 THEN '60-80%'
        WHEN 5 THEN 'Bottom 20%'
    END                                     AS segment_label,
    customers,
    mrr,
    avg_mrr,
    ROUND(mrr * 100.0 / SUM(mrr) OVER (), 1) AS pct_of_total_mrr,
    ROUND(SUM(mrr) OVER (ORDER BY revenue_quintile) * 100.0 / SUM(mrr) OVER (), 1) AS cumulative_mrr_pct
FROM quintile_summary
ORDER BY revenue_quintile;
