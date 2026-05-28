-- =============================================================================
-- Project:  SaaS Customer Health & Churn Analysis
-- Script:   05_customer_segments.sql
-- Purpose:  Customer segmentation and health scoring
--           Creates actionable segments for the CS team to act on
-- Author:   Simone D'Angelo
-- Date:     2026-05-27
-- =============================================================================

SET search_path = saas_churn;

-- =============================================================================
-- SECTION 1: RFM-Style Segmentation (adapted for SaaS)
-- In SaaS: Recency → Tenure, Frequency → Service Usage, Monetary → MRR
-- =============================================================================

-- 1A: Percentile rankings across key dimensions
DROP TABLE IF EXISTS customer_scores;

CREATE TABLE customer_scores AS
WITH percentile_ranks AS (
    SELECT
        customer_id,
        monthly_charges,
        tenure,
        num_services,
        is_autopay,
        has_tech_support,
        contract,
        churn_flag,

        -- Tenure score: longer tenure = lower churn risk (higher score)
        NTILE(5) OVER (ORDER BY tenure ASC)              AS tenure_score_raw,  -- 1=new, 5=veteran
        -- Charges score: higher spend = more engaged/committed
        NTILE(5) OVER (ORDER BY monthly_charges ASC)     AS charge_score_raw,  -- 1=low, 5=high
        -- Services score: more add-ons = more sticky
        NTILE(5) OVER (ORDER BY num_services ASC)        AS service_score_raw  -- 1=bare, 5=fully loaded

    FROM customers
),
health_scored AS (
    SELECT
        *,
        -- Tenure score: 0-12m = 10pts, 13-24m = 25pts, 25-48m = 40pts, 49-72m = 50pts
        CASE
            WHEN tenure BETWEEN 0  AND 12 THEN 10
            WHEN tenure BETWEEN 13 AND 24 THEN 25
            WHEN tenure BETWEEN 25 AND 48 THEN 40
            WHEN tenure BETWEEN 49 AND 72 THEN 50
        END                                              AS tenure_pts,

        -- Contract score: M2M=5, 1yr=15, 2yr=25 pts
        CASE contract
            WHEN 'Month-to-month' THEN 5
            WHEN 'One year'       THEN 15
            WHEN 'Two year'       THEN 25
        END                                              AS contract_pts,

        -- Services: each service = 3 points (max 18 pts)
        num_services * 3                                 AS service_pts,

        -- Auto-pay bonus: 7 pts
        CASE WHEN is_autopay THEN 7 ELSE 0 END           AS autopay_pts,

        -- Tech support bonus: key retention factor
        CASE WHEN has_tech_support THEN 5 ELSE 0 END     AS support_pts

    FROM percentile_ranks
)
SELECT
    customer_id,
    monthly_charges,
    tenure,
    num_services,
    is_autopay,
    has_tech_support,
    contract,
    churn_flag,
    tenure_score_raw,
    charge_score_raw,
    service_score_raw,

    -- Composite health score (0–100 scale)
    -- Max possible: 50 + 25 + 18 + 7 + 5 = 105 → normalize to 100
    LEAST(
        ROUND((tenure_pts + contract_pts + service_pts + autopay_pts + support_pts) * 100.0 / 105, 0),
        100
    )                                                    AS health_score,

    -- Health tier classification
    CASE
        WHEN ROUND((tenure_pts + contract_pts + service_pts + autopay_pts + support_pts) * 100.0 / 105, 0) >= 70
             THEN 'Healthy'
        WHEN ROUND((tenure_pts + contract_pts + service_pts + autopay_pts + support_pts) * 100.0 / 105, 0) >= 40
             THEN 'Needs Attention'
        ELSE 'At Risk'
    END                                                  AS health_tier

FROM health_scored;

-- Index for fast filtering
CREATE INDEX idx_scores_health ON customer_scores(health_tier);
CREATE INDEX idx_scores_churn ON customer_scores(churn_flag);


-- =============================================================================
-- SECTION 2: Validate Health Score Against Actual Churn
-- A good health score should have high churn in "At Risk" tier
-- =============================================================================

SELECT
    health_tier,
    COUNT(*)                                AS total_customers,
    SUM(churn_flag)                         AS churned,
    ROUND(AVG(churn_flag) * 100, 1)         AS churn_rate_pct,
    ROUND(AVG(health_score), 1)             AS avg_health_score,
    ROUND(AVG(monthly_charges), 2)          AS avg_mrr
FROM customer_scores
GROUP BY health_tier
ORDER BY avg_health_score DESC;


-- =============================================================================
-- SECTION 3: Actionable Customer Lists for CS Team
-- =============================================================================

-- 3A: Priority intervention list — At Risk, NOT yet churned, high revenue
SELECT
    customer_id,
    health_score,
    health_tier,
    monthly_charges,
    tenure,
    contract,
    is_autopay,
    has_tech_support,
    num_services,
    -- Suggested action based on profile
    CASE
        WHEN contract = 'Month-to-month' AND monthly_charges > 70
            THEN 'Offer annual contract discount'
        WHEN NOT is_autopay
            THEN 'Migration to auto-pay campaign'
        WHEN NOT has_tech_support AND monthly_charges > 60
            THEN 'Upsell tech support bundle'
        ELSE 'High-touch CSM outreach'
    END                                     AS recommended_action
FROM customer_scores
WHERE churn_flag = 0
  AND health_tier = 'At Risk'
ORDER BY monthly_charges DESC
LIMIT 100;


-- 3B: Expansion opportunity list — Healthy customers with low service count
--     These are safe accounts to upsell
SELECT
    customer_id,
    health_score,
    monthly_charges,
    tenure,
    contract,
    num_services,
    -- Services they don't have yet
    CASE
        WHEN NOT has_tech_support THEN 'Tech Support'
        WHEN NOT is_autopay       THEN 'Auto-pay setup'
        ELSE 'Premium plan upgrade'
    END                                     AS upsell_opportunity
FROM customer_scores
WHERE churn_flag = 0
  AND health_tier = 'Healthy'
  AND num_services <= 2
  AND tenure > 24  -- Long-tenured = trusted relationship
ORDER BY monthly_charges DESC
LIMIT 50;


-- =============================================================================
-- SECTION 4: Executive Summary Segment View
-- =============================================================================

SELECT
    health_tier,
    COUNT(*) FILTER (WHERE churn_flag = 0)                              AS active_customers,
    COUNT(*) FILTER (WHERE churn_flag = 1)                              AS churned_customers,
    ROUND(SUM(monthly_charges) FILTER (WHERE churn_flag = 0), 0)        AS active_mrr,
    ROUND(AVG(churn_flag) * 100, 1)                                     AS churn_rate_pct,
    ROUND(AVG(health_score), 0)                                         AS avg_health_score
FROM customer_scores
GROUP BY health_tier
ORDER BY avg_health_score DESC;
