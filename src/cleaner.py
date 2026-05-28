"""
cleaner.py
==========
Data cleaning pipeline for the Telco Churn dataset.

Cleaning philosophy:
  - Be explicit about every transformation (no silent mutations)
  - Log what was changed and why
  - Preserve original data — always work on copies
  - Validate after cleaning, not just before
"""

import pandas as pd
from typing import Tuple


def clean_churn_data(df: pd.DataFrame, verbose: bool = True) -> Tuple[pd.DataFrame, dict]:
    """
    Full cleaning pipeline for the raw Telco Churn dataset.

    Steps performed:
      1. Standardize column names (snake_case)
      2. Trim whitespace from all string columns
      3. Fix TotalCharges type issue (blank strings → impute with MonthlyCharges)
      4. Normalize SeniorCitizen (0/1 integer → Yes/No string)
      5. Create binary churn_flag from Churn column

    Parameters
    ----------
    df : pd.DataFrame
        Raw DataFrame from load_raw_csv()
    verbose : bool
        Print cleaning summary if True

    Returns
    -------
    Tuple[pd.DataFrame, dict]
        (cleaned_df, cleaning_report)
    """
    df = df.copy()
    report = {}

    # ── Step 1: Standardize column names ──────────────────────────────────────
    column_mapping = {
        'customerID'       : 'customer_id',
        'gender'           : 'gender',
        'SeniorCitizen'    : 'senior_citizen',
        'Partner'          : 'partner',
        'Dependents'       : 'dependents',
        'tenure'           : 'tenure',
        'PhoneService'     : 'phone_service',
        'MultipleLines'    : 'multiple_lines',
        'InternetService'  : 'internet_service',
        'OnlineSecurity'   : 'online_security',
        'OnlineBackup'     : 'online_backup',
        'DeviceProtection' : 'device_protection',
        'TechSupport'      : 'tech_support',
        'StreamingTV'      : 'streaming_tv',
        'StreamingMovies'  : 'streaming_movies',
        'Contract'         : 'contract',
        'PaperlessBilling' : 'paperless_billing',
        'PaymentMethod'    : 'payment_method',
        'MonthlyCharges'   : 'monthly_charges',
        'TotalCharges'     : 'total_charges',
        'Churn'            : 'churn',
    }
    df = df.rename(columns=column_mapping)
    report['columns_renamed'] = len(column_mapping)

    # ── Step 2: Trim all string columns ───────────────────────────────────────
    str_cols = df.select_dtypes(include='object').columns
    df[str_cols] = df[str_cols].apply(lambda col: col.str.strip())

    # ── Step 3: Fix TotalCharges (stored as string, with blanks) ──────────────
    blank_total = (df['total_charges'] == '') | (df['total_charges'].isna())
    n_blank = blank_total.sum()

    # Impute blank TotalCharges with MonthlyCharges (new customers, no billing yet)
    df.loc[blank_total, 'total_charges'] = df.loc[blank_total, 'monthly_charges'].astype(str)
    df['total_charges'] = pd.to_numeric(df['total_charges'], errors='coerce')

    report['total_charges_imputed'] = n_blank
    report['total_charges_nulls_after_coerce'] = df['total_charges'].isna().sum()

    # ── Step 4: SeniorCitizen (0/1 → No/Yes string for consistency) ──────────
    df['senior_citizen'] = df['senior_citizen'].map({0: 'No', 1: 'Yes'})

    # ── Step 5: Create binary churn flag (target variable) ────────────────────
    df['churn_flag'] = (df['churn'] == 'Yes').astype(int)
    report['churn_rate_pct'] = round(df['churn_flag'].mean() * 100, 2)
    report['churned_count'] = df['churn_flag'].sum()
    report['retained_count'] = (df['churn_flag'] == 0).sum()

    # ── Step 6: Final null check ───────────────────────────────────────────────
    null_counts = df.isnull().sum()
    report['final_null_counts'] = null_counts[null_counts > 0].to_dict()
    report['total_rows'] = len(df)
    report['total_cols'] = len(df.columns)

    if verbose:
        _print_cleaning_report(report)

    return df, report


def _print_cleaning_report(report: dict) -> None:
    """Pretty-print the cleaning report."""
    print("\n" + "="*55)
    print("  DATA CLEANING REPORT")
    print("="*55)
    print(f"  Total rows      : {report['total_rows']:,}")
    print(f"  Total columns   : {report['total_cols']}")
    print(f"  Columns renamed : {report['columns_renamed']}")
    print(f"  TotalCharges imputed (blank → MonthlyCharges): {report['total_charges_imputed']}")
    print(f"  Overall churn rate: {report['churn_rate_pct']}%")
    print(f"  Churned: {report['churned_count']:,}  |  Retained: {report['retained_count']:,}")
    if report['final_null_counts']:
        print(f"  ⚠️  Remaining nulls: {report['final_null_counts']}")
    else:
        print("  ✅ No remaining nulls")
    print("="*55 + "\n")


def validate_cleaned_data(df: pd.DataFrame) -> bool:
    """
    Run post-cleaning assertions.
    Raises ValueError if any check fails.
    Returns True if all checks pass.

    In production, these assertions would be run as dbt tests or
    Great Expectations validations.
    """
    errors = []

    # No duplicate customer IDs
    n_dupes = df['customer_id'].duplicated().sum()
    if n_dupes > 0:
        errors.append(f"Found {n_dupes} duplicate customer IDs")

    # Churn flag is binary
    unexpected_churn = df['churn_flag'].isin([0, 1])
    if not unexpected_churn.all():
        errors.append("churn_flag contains values other than 0 and 1")

    # Tenure is non-negative
    if (df['tenure'] < 0).any():
        errors.append("Negative tenure values found")

    # Monthly charges in reasonable range
    if df['monthly_charges'].min() < 0:
        errors.append("Negative monthly charges found")
    if df['monthly_charges'].max() > 200:
        errors.append(f"Monthly charges exceeds $200: max={df['monthly_charges'].max()}")

    # Total charges >= monthly charges (or very close, for new customers)
    negative_total_delta = (df['total_charges'] < df['monthly_charges'] * 0.9).sum()
    if negative_total_delta > 20:
        errors.append(f"{negative_total_delta} rows have total_charges < monthly_charges")

    # No completely null rows
    all_null_rows = df.isnull().all(axis=1).sum()
    if all_null_rows > 0:
        errors.append(f"{all_null_rows} completely null rows found")

    if errors:
        error_msg = "\n".join([f"  ❌ {e}" for e in errors])
        raise ValueError(f"Data validation failed:\n{error_msg}")

    print("✅ All data validation checks passed")
    return True
