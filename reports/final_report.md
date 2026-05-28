# SaaS Customer Health & Churn Analysis
### Internal Report

**Prepared by:** Simone D'Angelo, Data Analyst  
**Date:** May 2026  
**Distribution:** VP Customer Success · CFO · Product Team  
**Dataset:** 7,043 B2B SaaS customer accounts (Telco Customer Churn, IBM/Kaggle)

---

## Executive Summary

TeleCore SaaS is losing customers at a rate of **26.5% per year** — more than three times the 5–7% benchmark for B2B SaaS. Across 7,043 accounts, 1,869 customers have already churned, representing **$1.67M in annualized revenue loss**. A further ~$858K ARR sits in accounts that are still active but carry a high-risk profile.

The data points to a clear hierarchy of churn drivers: contract structure matters more than anything else, followed closely by how long a customer has been with us and how many services they actually use. Month-to-month customers churn at 42.7% while two-year contract holders churn at 2.8% — a 15-fold difference that represents the single largest lever available to the retention team.

Four interventions are recommended, with a combined estimated ARR recovery of $725K–$1.45M against roughly $233K in program costs.

---

## 1. Methodology

### Data

The IBM Telco Customer Churn dataset (7,043 accounts, 21 variables) covers contract type, service subscriptions, billing details, payment method, and churn status. It is a cross-sectional snapshot rather than a time-series event log, which has implications for cohort analysis noted in the Limitations section.

Eleven records had blank `TotalCharges` values — all were customers with zero months of tenure (not yet billed). These were imputed with `MonthlyCharges` rather than dropped, which is the correct handling for new accounts. No duplicate customer IDs were found. All validation checks passed prior to analysis.

### Approach

After cleaning and validation, twelve derived features were engineered — including tenure lifecycle buckets, a service depth count, an auto-pay flag, and a composite customer health score. Churn rates were then calculated across every major dimension individually, then cross-tabulated to surface segment combinations. Statistical significance of tenure differences between churned and retained populations was confirmed using a Mann-Whitney U test (chosen because tenure is not normally distributed). A revenue model was built to translate churn rates into MRR and ARR impact. Finally, a 0–100 health score was constructed from five weighted signals to give the CS team a single prioritisation metric per account.

**Tools:** PostgreSQL 15 (cohort queries, window functions, segmentation), Python 3.11 (pandas, NumPy, SciPy, Seaborn, Matplotlib). All SQL and Python code is in the accompanying repository.

---

## 2. Findings

### 2.1 Overall Churn Picture

| Metric | Value |
|--------|-------|
| Total accounts | 7,043 |
| Churned | 1,869 (26.5%) |
| Active | 5,174 (73.5%) |
| B2B SaaS benchmark | 5–7% |
| Gap to benchmark | +19.5 percentage points |
| Total MRR (all accounts) | $456,100 |
| MRR lost to churned accounts | $139,130 |
| Revenue churn rate | 30.5% |
| Annualized revenue lost | $1.67M |

The revenue churn rate (30.5%) actually exceeds the customer churn rate (26.5%), which means churned customers were spending slightly above average. This rules out the possibility that we're mainly losing low-value accounts.

### 2.2 Contract Type

*See `assets/charts/02_churn_by_contract.png`*

| Contract | Customers | Churn Rate | Avg Tenure |
|----------|-----------|------------|------------|
| Month-to-month | 3,875 | 42.7% | 17.8 months |
| One year | 1,473 | 11.3% | 42.1 months |
| Two year | 1,695 | 2.8% | 56.7 months |

Month-to-month is by far the most common contract type (55% of the base) and by far the most dangerous. Even a modest conversion of M2M customers to annual contracts would have a disproportionate impact on retention. Notably, the average tenure of two-year contract holders is 56 months — these customers are genuinely embedded in the product.

### 2.3 Customer Tenure

*See `assets/charts/03_tenure_distribution_kde.png`*

| Tenure Band | Churn Rate |
|-------------|------------|
| 0–12 months | 47.4% |
| 13–24 months | 28.7% |
| 25–48 months | 20.4% |
| 49–72 months | 9.5% |

Nearly half of all customers who joined and are in their first year have already churned. The survival curve is steep early and flattens dramatically after 24 months. Median tenure for churned customers is 10 months; for retained customers it is 38 months. The difference is statistically significant (Mann-Whitney U, p < 0.001), and the effect size is large enough to be practically meaningful, not just statistically so.

The implication is straightforward: if we can get customers past the 24-month mark, we've largely solved churn. The onboarding and early-lifecycle experience is where the battle is won or lost.

### 2.4 Payment Method

*See `assets/charts/07_churn_by_payment_method.png`*

| Payment Method | Churn Rate |
|----------------|------------|
| Electronic check | 45.3% |
| Mailed check | 19.1% |
| Bank transfer (automatic) | 16.7% |
| Credit card (automatic) | 15.2% |

Electronic check customers churn at 45.3% — nearly three times the rate of automatic payment customers. This is worth treating as a behavioral signal rather than a causal mechanism. Customers who haven't set up auto-pay may simply be less committed to the product, or may be in a more fragile financial position. Either way, it's a reliable early-warning indicator.

### 2.5 Service Depth

*See `assets/charts/08_churn_by_num_services.png`*

| Add-on Services Used | Churn Rate |
|----------------------|------------|
| 0 | 58.5% |
| 1–2 | 41.2% |
| 3–4 | 24.7% |
| 5–6 | 8.3% |

The relationship between service adoption and retention is consistent and large. Customers using five or more add-on services churn at just 8.3%. Each additional service creates switching cost and, presumably, genuine product value. Getting customers to adopt two or more services early in their lifecycle should be a core onboarding objective.

### 2.6 Highest-Risk Segment

*See `assets/charts/05_churn_heatmap_contract_internet.png`*

The cross-dimensional analysis identifies one particularly acute risk cluster: **month-to-month contract + fiber optic internet + electronic check payment + no tech support**. This group's churn rate is approximately 67%. There are 312 active customers matching this profile, generating $28,400/month in MRR. This is the most immediately actionable group for CSM intervention.

---

## 3. Customer Health Score

To give the CS team a single metric per account, a composite health score (0–100) was built from five signals: tenure, contract type, number of add-on services, payment method, and tech support status. Weights were assigned based on their observed correlation with churn.

*See `assets/charts/06_health_score_distribution.png`*

| Health Tier | Score Range | Customers | Churn Rate | Active MRR |
|-------------|-------------|-----------|------------|------------|
| Healthy | 70–100 | 2,154 | 7.4% | $147,211 |
| Needs Attention | 40–69 | 2,158 | 21.8% | $98,228 |
| At Risk | 0–39 | 2,731 | 45.4% | $71,548 |

At Risk customers churn at six times the rate of Healthy customers. The score successfully stratifies the base into meaningfully different risk profiles, which validates its use as a prioritisation tool. Of the 2,731 At Risk accounts, 1,492 are still active, generating $71,548/month (~$858K ARR) in revenue that is currently at elevated risk of leaving.

The health score is a heuristic model, not a statistically trained classifier. Its discrimination power has not been measured against a holdout set. Treat it as a triage tool, not a prediction — see Limitations.

---

## 4. Revenue Impact

### What We've Already Lost

| | Value |
|--|-------|
| MRR lost to churned accounts | $139,130/month |
| ARR equivalent | $1.67M |

### What Is Currently at Risk

| | Value |
|--|-------|
| At Risk tier — active MRR | $71,548/month |
| ARR equivalent | ~$858K |

### Intervention Scenarios

The table below models the revenue saved if retention programs succeed at converting or retaining a portion of at-risk accounts.

| Intervention | Target Segment | Est. Program Cost | ARR Recovered |
|-------------|----------------|-------------------|---------------|
| M2M → Annual contract campaign | 3,875 M2M customers | ~$45K | $280K–$560K |
| Auto-pay migration campaign | ~1,200 electronic check customers | ~$8K | $95K–$190K |
| Structured onboarding (0–90 day) | All new customers | ~$60K/yr | $150K–$300K |
| At-Risk CSM outreach program | ~500 highest-risk active accounts | ~$120K/yr | $200K–$400K |

**Total estimated ARR recovered: $725K–$1.45M** on ~$233K in combined program costs — a 3–6× return. These figures assume conservative success rates (10–20% conversion/retention improvement per program) and should be treated as directional estimates pending A/B test design.

---

## 5. Recommendations

### 1. Contract Migration Program — Priority: High

Offer a 10–15% discount on annual plans to month-to-month customers who have been active for at least three months. Prioritise accounts with monthly charges above $65 (above the median). The expected conversion rate based on comparable SaaS discount campaigns is 8–12%. At the lower end of that range, this recovers roughly $280K ARR. At the upper end, closer to $560K.

The discount is self-funding: a customer paying $70/month who converts to annual at a 15% discount ($59.50/month) still represents roughly 4× the lifetime value of a customer who churns at month 10.

### 2. Auto-Pay Migration Campaign — Priority: High

Run an in-app prompt and email campaign targeting electronic check customers. Offer one month free as a migration incentive. This is the lowest-cost intervention on the list ($8K in execution) relative to its upside ($95K–$190K ARR). Even if only 15% of electronic check customers convert to auto-pay and their churn rate improves to the auto-pay average, the math is strongly positive.

### 3. Structured Onboarding Program — Priority: High

Assign a CSM or automated onboarding sequence to every new customer for their first 90 days, with a specific objective: at least two add-on services adopted by day 60. The data shows that service depth is one of the strongest retention signals, and the 0–12 month window is where almost half of all churn happens. Fixing onboarding is fixing the root cause, not the symptom.

### 4. At-Risk Account CSM Prioritisation — Priority: Medium

Generate a weekly export of active accounts with health score below 40, sorted by MRR. Each CSM handles no more than 80 at-risk accounts. The outreach conversation should focus on the customer's specific risk profile — for a M2M + fiber + no tech support account, the pitch is a bundled annual plan with tech support included. For an electronic check customer, it's auto-pay migration with a small incentive.

---

## 6. Limitations

**Cross-sectional data.** The dataset is a snapshot, not a time-series event log. Cohort retention curves are approximated from tenure values rather than actual signup and cancellation dates. This means the survival analysis is directionally correct but not as precise as it would be with real event data.

**Heuristic health score.** The 0–100 health score has not been validated on a holdout set. It reflects which features correlate with churn in the historical data, but its discriminative power (AUC-ROC, precision/recall) has not been measured. A logistic regression or gradient boosting model with proper cross-validation would be the next step.

**No cost-of-acquisition data.** CAC is unavailable. Revenue impact calculations reflect MRR only — net customer economics (MRR minus CAC amortisation) would be a more accurate framing for the CFO.

**Correlation, not causation.** Electronic check payment correlates strongly with churn, but it is not necessarily causing it. It may be a proxy for financial risk, lower product engagement, or demographic factors not captured in this dataset. The recommended campaign (auto-pay migration) still makes sense regardless — but the causal mechanism is uncertain.

**Intervention ROI estimates are projections.** The recovery figures in Section 4 are based on assumed conversion rates. Actual results will depend on execution quality, timing, and market conditions. A/B testing is strongly recommended before scaling any of these programs.

---

## 7. Next Steps

**Week 1–2:** Export the At-Risk customer list from the health scoring output (`sql/05_customer_segments.sql`, Section 3A) and share with the CS team for immediate outreach.

**Month 1:** Design and launch the auto-pay migration email campaign — lowest cost, fastest to execute. Begin A/B testing the contract migration discount offer with a subset of M2M customers.

**Month 2–3:** Build a logistic regression churn model on this dataset with a proper 80/20 train/test split. Target AUC-ROC ≥ 0.80. Replace the heuristic health score with model-derived churn probabilities.

**Month 3–6:** If product event logging exists or can be instrumented, replace demographic proxies (tenure, contract type) with actual usage signals (login frequency, feature adoption, support ticket volume). This will substantially improve prediction accuracy. Connect model output to CRM for automated CSM alerting.
