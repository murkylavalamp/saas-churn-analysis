# SaaS Customer Health & Churn Analysis

End-to-end churn analysis for a B2B SaaS business — from raw data to segmented customer health scoring, SQL cohort analysis, and a prioritized retention roadmap. Built using Python, PostgreSQL, and real-world analytical workflows.

---

## Business Context

**Company:** TeleCore SaaS (simulated B2B telecommunications software company)  
**Analytical role:** Data Analyst — Customer Success & Retention Team  
**Stakeholders:** VP of Customer Success, CFO, Product Team

TeleCore has ~7,000 customers across three contract tiers. Leadership flagged that monthly churn was eroding ARR growth and needed to understand who was churning, why, and what to do about it.

---

## Business Problem & Objectives

Observed churn rate: **~26.5%** — more than three times the 5–7% B2B SaaS industry benchmark. The analysis targets three stakeholder questions:

1. **Who is churning?** — account-level and demographic patterns
2. **Why are they churning?** — product usage and billing signals
3. **What can we do?** — actionable recommendations with revenue impact estimates

### KPIs Tracked

| KPI | Definition |
|-----|-----------|
| Churn Rate | % of customers who cancelled in period |
| Monthly Revenue Churn | MRR lost to churned accounts |
| Customer Lifetime Value (LTV) | Avg monthly charges × avg tenure months |
| Retention Rate by Cohort | % of cohort still active after N months |
| Customer Health Score | Composite risk score (0–100) per account |

---

## Project Structure

```
01_saas_churn_analysis/
│
├── data/
│   ├── raw/                        # Original Kaggle CSV — unmodified
│   └── processed/                  # Cleaned, feature-engineered parquet files
│
├── notebooks/
│   └── 01_churn_analysis.ipynb     # Full EDA, feature engineering, health scoring
│
├── sql/
│   ├── 01_schema_setup.sql         # Table creation and data loading
│   ├── 02_data_validation.sql      # Quality checks and sanity assertions
│   ├── 03_churn_cohort_analysis.sql # Cohort retention, window functions
│   ├── 04_revenue_impact.sql       # MRR, ARR, revenue-at-risk modelling
│   └── 05_customer_segments.sql    # Health scoring and CS action lists
│
├── src/
│   ├── data_loader.py              # CSV and PostgreSQL ingestion
│   ├── cleaner.py                  # Cleaning pipeline with validation
│   ├── features.py                 # Feature engineering (22 derived features)
│   └── visualizations.py          # Reusable chart functions (8 charts)
│
├── assets/
│   └── charts/                     # Saved PNGs — referenced throughout the report
│
├── reports/
│   └── final_report.md             # Executive findings report
│
├── data_dictionary.md              # Column definitions and business logic
├── requirements.txt
├── .env.example                    # Environment variable template
└── .gitignore
```

---

## Tech Stack

| Layer | Tools |
|-------|-------|
| Database | PostgreSQL 15 |
| Language | Python 3.11 |
| Data manipulation | pandas, NumPy |
| Visualization | Matplotlib, Seaborn |
| Statistical analysis | SciPy |
| Notebook environment | JupyterLab |

---

## Dataset

**Source:** [Telco Customer Churn — Kaggle (IBM Sample Dataset)](https://www.kaggle.com/datasets/blastchar/telco-customer-churn)

**Size:** 7,043 customers × 21 features

**Key fields:** `customerID`, `tenure`, `Contract`, `InternetService`, `PaymentMethod`, `MonthlyCharges`, `TotalCharges`, `Churn`

> Download the CSV and place it at `data/raw/WA_Fn-UseC_-Telco-Customer-Churn.csv` before running the notebook.

---

## Installation & Setup

```bash
git clone https://github.com/murkylavalamp/saas-churn-analysis.git
cd saas-churn-analysis

python -m venv venv
source venv/bin/activate       # Windows: venv\Scripts\activate

pip install -r requirements.txt

jupyter lab
```

**PostgreSQL setup:**
```bash
createdb saas_churn
psql -d saas_churn -f sql/01_schema_setup.sql
# Then load the CSV per the \COPY instruction in that script
```

Copy `.env.example` to `.env` and fill in your PostgreSQL credentials before running any database-connected scripts.

---

## Analytical Workflow

```
Raw CSV → Validation → Cleaning → Feature Engineering → EDA
    → SQL Cohort Analysis → Health Scoring → Visualizations → Report
```

The notebook (`notebooks/01_churn_analysis.ipynb`) walks through each step sequentially. SQL scripts in `sql/` contain the same logic in PostgreSQL for production use.

---

## Key Findings

- **Contract type is the dominant driver.** Month-to-month customers churn at 42.7% vs 2.8% for two-year contract holders — a 15× gap. See `assets/charts/02_churn_by_contract.png`.
- **New customers are the most vulnerable.** Churn rate in months 0–12 is 47.4%, falling to 9.5% for customers past 48 months. Median tenure: 10 months (churned) vs 38 months (retained), Mann-Whitney U p < 0.001.
- **Electronic check is a reliable churn signal.** These customers churn at 45.3% — nearly 3× the rate of auto-pay customers (15–17%). See `assets/charts/07_churn_by_payment_method.png`.
- **Service depth predicts stickiness.** Customers using 5–6 add-on services churn at 8.3%; those using none churn at 58.5%. See `assets/charts/08_churn_by_num_services.png`.
- **Revenue impact.** $139K MRR ($1.67M ARR) is lost to churn annually. A further $72K MRR (~$858K ARR) is at risk from active customers currently scoring as At Risk.

Full analysis and recommendations: [`reports/final_report.md`](reports/final_report.md)

---

## Visualizations

All charts are saved to `assets/charts/` after running the notebook.

| File | Description |
|------|-------------|
| `01_churn_overview_donut.png` | Overall churn vs retention rate |
| `02_churn_by_contract.png` | Churn rate by contract type |
| `03_tenure_distribution_kde.png` | Tenure KDE: churned vs retained |
| `04_monthly_charges_violin.png` | Monthly charges distribution by churn status |
| `05_churn_heatmap_contract_internet.png` | Churn rate: contract × internet service |
| `06_health_score_distribution.png` | Health score histogram by churn status |
| `07_churn_by_payment_method.png` | Churn rate by payment method |
| `08_churn_by_num_services.png` | Churn rate vs number of add-on services |
| `09_correlation_heatmap.png` | Feature correlation matrix |

---

## Business Recommendations

Full modelling in [`reports/final_report.md`](reports/final_report.md). Summary:

1. **Contract migration program** — offer 10–15% discount to M2M customers with 3+ months tenure; projected $280K–$560K ARR recovered
2. **Auto-pay migration campaign** — in-app + email nudge for electronic check customers; low cost, $95K–$190K ARR impact
3. **Structured onboarding (0–90 days)** — CSM-led or automated; targets the 47.4% first-year churn rate
4. **At-Risk account prioritisation** — weekly export of health score < 40 accounts for CSM outreach

Combined intervention ROI estimate: **3–6×** on ~$233K spend.

---

## Limitations & Future Work

The dataset is a cross-sectional snapshot, not a true event log, so cohort curves are approximated from tenure rather than actual signup dates. The health score is a heuristic — next steps include a logistic regression or gradient boosting model with proper AUC-ROC validation, a Streamlit dashboard for the CS team, and integration with a CRM for real-time alerting.
