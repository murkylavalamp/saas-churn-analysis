# Data Dictionary — SaaS Churn Analysis

**Dataset:** Telco Customer Churn (IBM/Kaggle)  
**Last updated:** 2026-05-27

---

## Raw Dataset Columns

These match the original Kaggle CSV exactly. Column names are converted to snake_case during the cleaning step.

| Original Column | Cleaned Name | Type | Description | Values |
|-----------------|-------------|------|-------------|--------|
| `customerID` | `customer_id` | VARCHAR | Unique customer identifier | 7,043 distinct values |
| `gender` | `gender` | VARCHAR | Customer gender | `Male`, `Female` |
| `SeniorCitizen` | `senior_citizen` | INTEGER → VARCHAR | Whether customer is 65+ | `0`/`1` in raw; normalized to `No`/`Yes` |
| `Partner` | `partner` | VARCHAR | Has a domestic partner | `Yes`, `No` |
| `Dependents` | `dependents` | VARCHAR | Has dependents | `Yes`, `No` |
| `tenure` | `tenure` | INTEGER | Months as a customer | 0–72 |
| `PhoneService` | `phone_service` | VARCHAR | Has phone service | `Yes`, `No` |
| `MultipleLines` | `multiple_lines` | VARCHAR | Multiple phone lines | `Yes`, `No`, `No phone service` |
| `InternetService` | `internet_service` | VARCHAR | Internet service type | `DSL`, `Fiber optic`, `No` |
| `OnlineSecurity` | `online_security` | VARCHAR | Online security add-on | `Yes`, `No`, `No internet service` |
| `OnlineBackup` | `online_backup` | VARCHAR | Online backup add-on | `Yes`, `No`, `No internet service` |
| `DeviceProtection` | `device_protection` | VARCHAR | Device protection add-on | `Yes`, `No`, `No internet service` |
| `TechSupport` | `tech_support` | VARCHAR | Tech support add-on | `Yes`, `No`, `No internet service` |
| `StreamingTV` | `streaming_tv` | VARCHAR | Streams TV content | `Yes`, `No`, `No internet service` |
| `StreamingMovies` | `streaming_movies` | VARCHAR | Streams movies | `Yes`, `No`, `No internet service` |
| `Contract` | `contract` | VARCHAR | Contract term | `Month-to-month`, `One year`, `Two year` |
| `PaperlessBilling` | `paperless_billing` | VARCHAR | Enrolled in paperless billing | `Yes`, `No` |
| `PaymentMethod` | `payment_method` | VARCHAR | Payment method | `Electronic check`, `Mailed check`, `Bank transfer (automatic)`, `Credit card (automatic)` |
| `MonthlyCharges` | `monthly_charges` | FLOAT | Current monthly bill ($) | $18.25 – $118.75 |
| `TotalCharges` | `total_charges` | VARCHAR → FLOAT | Lifetime spend ($) | Stored as string in raw data; 11 blank values (new customers, imputed with `monthly_charges`) |
| `Churn` | `churn` | VARCHAR | Whether customer cancelled | `Yes`, `No` |

---

## Engineered Features

Created in `src/features.py` via `engineer_features()`. All features are added to the cleaned DataFrame and saved to `data/processed/`.

### Target Variable

| Column | Type | Description |
|--------|------|-------------|
| `churn_flag` | INT | Binary: `1` = churned, `0` = retained. Derived from `churn`. |

### Tenure Features

| Column | Type | Description |
|--------|------|-------------|
| `tenure_bucket` | Categorical | Lifecycle stage: `0-12m`, `13-24m`, `25-48m`, `49-72m` |
| `is_new_customer` | INT (0/1) | `1` if tenure < 6 months — highest churn risk window |
| `tenure_normalized` | FLOAT | Tenure scaled to 0–1; useful for distance-based models |

### Service Engagement Features

| Column | Type | Description |
|--------|------|-------------|
| `num_services` | INT | Count of active add-on services (0–6). Covers: online_security, online_backup, device_protection, tech_support, streaming_tv, streaming_movies |
| `has_any_security` | INT (0/1) | `1` if customer has at least one security-type service (security, backup, device protection, tech support) |
| `is_streaming_only` | INT (0/1) | `1` if customer uses streaming but no security services — higher churn risk profile |
| `service_depth` | Categorical | Binned service count: `None`, `Low (1-2)`, `Medium (3-4)`, `High (5-6)` |

### Billing & Payment Features

| Column | Type | Description |
|--------|------|-------------|
| `charge_per_service` | FLOAT | `monthly_charges / (num_services + 1)` — value proxy; high value with low services may signal churn risk |
| `charge_consistency_ratio` | FLOAT | `total_charges / (monthly_charges × tenure)` — should be ~1.0 for a steady customer; deviations flag plan changes or promotions |
| `is_high_spender` | INT (0/1) | `1` if `monthly_charges` ≥ 75th percentile |
| `is_autopay` | INT (0/1) | `1` if payment method is bank transfer or credit card (automatic) |
| `is_electronic_check` | INT (0/1) | `1` if payment method is electronic check — strongest individual churn signal |

### Encoded Demographic & Contract Features

| Column | Type | Description |
|--------|------|-------------|
| `partner_flag` | INT (0/1) | Binary encoding of `partner` |
| `dependents_flag` | INT (0/1) | Binary encoding of `dependents` |
| `phone_service_flag` | INT (0/1) | Binary encoding of `phone_service` |
| `paperless_billing_flag` | INT (0/1) | Binary encoding of `paperless_billing` |
| `senior_citizen_flag` | INT (0/1) | Binary encoding of `senior_citizen` |
| `contract_ordinal` | INT | Ordinal: Month-to-month=0, One year=1, Two year=2 |
| `has_internet` | INT (0/1) | `1` if internet_service is not `No` |
| `has_fiber` | INT (0/1) | `1` if internet_service is `Fiber optic` |

### Customer Health Score

| Column | Type | Description |
|--------|------|-------------|
| `health_score` | FLOAT (0–100) | Composite score. Higher = healthier (lower churn risk). Weights: tenure (up to 50 pts), contract (up to 25 pts), services (up to 18 pts), auto-pay (7 pts), tech support (5 pts). Max raw = 105, normalized to 100. |
| `health_tier` | Categorical | `At Risk` (score < 40), `Needs Attention` (40–69), `Healthy` (70–100) |

---

## Business Definitions

**Churn:** A customer is marked churned when their subscription was not renewed at the end of a billing period.

**MRR (Monthly Recurring Revenue):** Sum of `monthly_charges` across active customers in the current period.

**Revenue churn rate:** MRR lost to churned accounts divided by total MRR (including churned accounts). Distinct from customer churn rate.

**MRR at risk:** `monthly_charges` summed across active accounts in the `At Risk` health tier.

**LTV (simplified):** `avg_monthly_charges × avg_tenure_months` — does not include discount rate or CAC. Treat as a directional estimate.

**Retention rate (cohort):** Proportion of customers in a given tenure band still active, as a proxy for survival over time. Note: without true signup/cancellation timestamps, this is an approximation.

---

## Data Quality Notes

- `TotalCharges` has 11 blank strings in the raw CSV. These correspond to customers with `tenure = 0` (newly signed, not yet billed). These are imputed with `MonthlyCharges` rather than dropped, to preserve all 7,043 records.
- `SeniorCitizen` is the only column encoded as 0/1 integer in the raw data — all others use `Yes`/`No`. Normalized during cleaning.
- No duplicate `customerID` values exist.
- No missing values remain after cleaning (confirmed by `validate_cleaned_data()` in `src/cleaner.py`).
