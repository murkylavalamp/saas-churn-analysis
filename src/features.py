"""
features.py
===========
Feature engineering for the SaaS Churn Analysis project.

Feature engineering is where analytical thinking meets domain knowledge.
Each feature here has a business rationale — we're not just creating variables,
we're encoding hypotheses about customer behavior.
"""

import pandas as pd


# ── Service column list (used in multiple functions) ──────────────────────────
SERVICE_COLS = [
    'online_security', 'online_backup', 'device_protection',
    'tech_support', 'streaming_tv', 'streaming_movies'
]

BOOLEAN_COLS = [
    'partner', 'dependents', 'phone_service', 'paperless_billing',
    'senior_citizen'
]


def engineer_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Main feature engineering pipeline.
    Returns the DataFrame with all derived columns added.

    Business rationale documented inline for each feature.
    """
    df = df.copy()

    # ── Tenure features ────────────────────────────────────────────────────────
    df = _add_tenure_features(df)

    # ── Service engagement features ────────────────────────────────────────────
    df = _add_service_features(df)

    # ── Billing / pricing features ─────────────────────────────────────────────
    df = _add_billing_features(df)

    # ── Boolean encoding ───────────────────────────────────────────────────────
    df = _encode_boolean_cols(df)

    # ── Customer health score ──────────────────────────────────────────────────
    df = _compute_health_score(df)

    return df


def _add_tenure_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Tenure is one of the strongest predictors of churn.
    New customers are the most vulnerable.

    Feature: tenure_bucket
    Rationale: Bucketing smooths the continuous signal and aligns with
    how CS teams think about lifecycle stages (onboarding, growth, mature).
    """
    df['tenure_bucket'] = pd.cut(
        df['tenure'],
        bins=[-1, 12, 24, 48, 72],
        labels=['0-12m', '13-24m', '25-48m', '49-72m']
    )

    # Feature: is_new_customer (binary flag for < 6 months)
    # Rationale: First 6 months = highest churn risk window in most SaaS products
    df['is_new_customer'] = (df['tenure'] < 6).astype(int)

    # Feature: tenure_normalized (0–1 scale)
    # Rationale: Useful for scoring models and distance metrics
    df['tenure_normalized'] = df['tenure'] / df['tenure'].max()

    return df


def _add_service_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Service engagement is a strong stickiness proxy.
    More services = more value delivered = harder to leave.

    Feature: num_services
    Rationale: Customers using 4+ services have significantly lower churn
    in most SaaS datasets — this is "product stickiness"
    """
    # Count Yes values across service columns
    df['num_services'] = (
        df[SERVICE_COLS]
        .apply(lambda col: (col == 'Yes').astype(int))
        .sum(axis=1)
    )

    # Feature: has_any_security_service
    # Rationale: Security services are "peace of mind" — once adopted, rarely removed
    security_services = ['online_security', 'online_backup', 'device_protection', 'tech_support']
    df['has_any_security'] = (
        df[security_services]
        .apply(lambda col: (col == 'Yes').astype(int))
        .sum(axis=1) > 0
    ).astype(int)

    # Feature: is_streaming_only
    # Rationale: Customers using ONLY streaming (no security services) may churn
    # when they find a cheaper streaming alternative
    df['is_streaming_only'] = (
        ((df['streaming_tv'] == 'Yes') | (df['streaming_movies'] == 'Yes')) &
        (df[security_services].apply(lambda c: c == 'Yes').sum(axis=1) == 0)
    ).astype(int)

    # Feature: service_depth_bucket
    df['service_depth'] = pd.cut(
        df['num_services'],
        bins=[-1, 0, 2, 4, 6],
        labels=['None', 'Low (1-2)', 'Medium (3-4)', 'High (5-6)']
    )

    return df


def _add_billing_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Billing patterns reveal customer health and financial stress signals.

    Feature: charge_per_service
    Rationale: If a customer pays a lot but uses few services, they may feel
    they're getting poor value → churn risk
    """
    # Avoid division by zero for customers with 0 add-on services
    df['charge_per_service'] = df['monthly_charges'] / (df['num_services'] + 1)

    # Feature: total_charge_ratio
    # Rationale: total_charges / (monthly_charges × tenure) ≈ 1.0 for consistent payers
    # Deviations might indicate plan changes, promotions, or data issues
    expected_total = df['monthly_charges'] * df['tenure'].clip(lower=1)
    df['charge_consistency_ratio'] = (df['total_charges'] / expected_total).round(3)

    # Feature: is_high_spender (above 75th percentile of monthly charges)
    p75 = df['monthly_charges'].quantile(0.75)
    df['is_high_spender'] = (df['monthly_charges'] >= p75).astype(int)

    # Feature: is_autopay
    # Rationale: Auto-pay customers churn at ~half the rate of manual payers
    # It's both a convenience and a commitment signal
    df['is_autopay'] = df['payment_method'].isin([
        'Bank transfer (automatic)', 'Credit card (automatic)'
    ]).astype(int)

    # Feature: is_electronic_check
    # Rationale: Electronic check customers have highest churn — worth flagging separately
    df['is_electronic_check'] = (df['payment_method'] == 'Electronic check').astype(int)

    return df


def _encode_boolean_cols(df: pd.DataFrame) -> pd.DataFrame:
    """
    Convert Yes/No columns to 1/0 for easier math and modeling.
    """
    for col in BOOLEAN_COLS:
        if col in df.columns:
            df[f'{col}_flag'] = (df[col] == 'Yes').astype(int)

    # Contract type — ordinal encoding (more committed = higher value)
    contract_order = {'Month-to-month': 0, 'One year': 1, 'Two year': 2}
    df['contract_ordinal'] = df['contract'].map(contract_order)

    # Internet service — nominal encoding
    df['has_internet'] = (df['internet_service'] != 'No').astype(int)
    df['has_fiber'] = (df['internet_service'] == 'Fiber optic').astype(int)

    return df


def _compute_health_score(df: pd.DataFrame) -> pd.DataFrame:
    """
    Compute a composite customer health score (0–100).

    Scoring methodology:
    - Tenure:    up to 50 points (most predictive)
    - Contract:  up to 25 points (commitment signal)
    - Services:  up to 18 points (stickiness)
    - Auto-pay:  7 points (convenience/commitment)
    - Tech support: 5 points (retention anchor)

    Business use: CS teams use health scores to prioritize outreach.
    Score < 40 = "red account" → immediate CSM action
    Score 40–69 = "amber account" → scheduled check-in
    Score ≥ 70 = "green account" → expand/upsell focus
    """
    # Tenure points (0–50)
    tenure_pts = pd.cut(
        df['tenure'],
        bins=[-1, 12, 24, 48, 72],
        labels=[10, 25, 40, 50]
    ).astype(float)

    # Contract points
    contract_pts = df['contract'].map({
        'Month-to-month': 5,
        'One year'      : 15,
        'Two year'      : 25
    })

    # Services points (3 pts each, max 18)
    service_pts = df['num_services'] * 3

    # Auto-pay bonus
    autopay_pts = df['is_autopay'] * 7

    # Tech support bonus
    tech_pts = (df['tech_support'] == 'Yes').astype(int) * 5

    # Raw score (max ~105)
    raw_score = tenure_pts + contract_pts + service_pts + autopay_pts + tech_pts

    # Normalize to 0–100
    df['health_score'] = (raw_score / 105 * 100).clip(0, 100).round(1)

    # Health tier
    df['health_tier'] = pd.cut(
        df['health_score'],
        bins=[-1, 39, 69, 100],
        labels=['At Risk', 'Needs Attention', 'Healthy']
    )

    return df


def get_feature_summary(df: pd.DataFrame) -> pd.DataFrame:
    """
    Return a summary of engineered feature distributions.
    Useful for sanity checks and README documentation.
    """
    engineered_cols = [
        'tenure_bucket', 'num_services', 'service_depth', 'charge_per_service',
        'is_autopay', 'is_new_customer', 'has_any_security', 'health_score', 'health_tier'
    ]
    existing = [c for c in engineered_cols if c in df.columns]
    return df[existing].describe(include='all').T
