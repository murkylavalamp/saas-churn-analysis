"""
visualizations.py
=================
Reusable, publication-quality chart functions for the Churn Analysis project.

Design principles:
  - Every function saves the chart AND returns the figure
  - Consistent color palette and style throughout
  - Annotations included — charts should be self-explanatory
  - Business labels (not technical ones) on all axes

Color palette: red for churn/risk, green for retained/healthy, blue for neutral
"""

import matplotlib.pyplot as plt
import seaborn as sns
import pandas as pd
import numpy as np
from pathlib import Path

# ── Global style configuration ─────────────────────────────────────────────────
CHART_DIR = Path(__file__).resolve().parent.parent / "assets" / "charts"
CHART_DIR.mkdir(parents=True, exist_ok=True)

# Color palette
COLORS = {
    'churn'    : '#E63946',   # Red for churned customers
    'retained' : '#2A9D8F',   # Teal for retained customers
    'neutral'  : '#457B9D',   # Blue for neutral segments
    'warning'  : '#E9C46A',   # Amber for medium risk
    'dark'     : '#1D3557',   # Dark navy for titles/text
    'light_bg' : '#F8F9FA',   # Light background
}

# Default style
plt.rcParams.update({
    'font.family'     : 'DejaVu Sans',
    'font.size'       : 11,
    'axes.titlesize'  : 14,
    'axes.titleweight': 'bold',
    'axes.labelsize'  : 11,
    'figure.facecolor': 'white',
    'axes.facecolor'  : COLORS['light_bg'],
    'axes.spines.top' : False,
    'axes.spines.right': False,
})


def _save(fig: plt.Figure, filename: str) -> Path:
    """Save figure to assets/charts/ and return path."""
    path = CHART_DIR / f"{filename}.png"
    fig.savefig(path, dpi=150, bbox_inches='tight', facecolor='white')
    print(f"  💾 Saved: {path.name}")
    return path


def plot_churn_overview(df: pd.DataFrame) -> plt.Figure:
    """
    Donut chart showing overall churn vs retention rate.
    Simple but always the first slide in a churn deck.
    """
    churn_rate = df['churn_flag'].mean() * 100
    retained_rate = 100 - churn_rate
    churned_n = df['churn_flag'].sum()
    retained_n = len(df) - churned_n

    fig, ax = plt.subplots(figsize=(7, 7))

    wedges, texts, autotexts = ax.pie(
        [retained_rate, churn_rate],
        labels=[f'Retained\n({retained_n:,})', f'Churned\n({churned_n:,})'],
        colors=[COLORS['retained'], COLORS['churn']],
        autopct='%1.1f%%',
        startangle=90,
        wedgeprops=dict(width=0.5, edgecolor='white', linewidth=3),
        textprops={'fontsize': 13}
    )
    for autotext in autotexts:
        autotext.set_fontsize(14)
        autotext.set_fontweight('bold')
        autotext.set_color('white')

    ax.set_title(
        f"Overall Churn Rate: {churn_rate:.1f}%\n"
        f"Industry benchmark: 5–7% | Action needed above 10%",
        fontsize=14, fontweight='bold', color=COLORS['dark'], pad=20
    )
    fig.tight_layout()
    _save(fig, '01_churn_overview_donut')
    return fig


def plot_churn_by_contract(df: pd.DataFrame) -> plt.Figure:
    """
    Grouped bar chart: churn rate by contract type.
    This is almost always the most impactful single chart in a churn analysis.
    """
    summary = (
        df.groupby('contract')['churn_flag']
        .agg(['mean', 'count', 'sum'])
        .reset_index()
        .rename(columns={'mean': 'churn_rate', 'count': 'total', 'sum': 'churned'})
    )
    summary['churn_rate_pct'] = summary['churn_rate'] * 100
    summary = summary.sort_values('churn_rate_pct', ascending=False)

    fig, ax = plt.subplots(figsize=(9, 6))
    colors = [COLORS['churn'], COLORS['warning'], COLORS['retained']]
    bars = ax.bar(
        summary['contract'],
        summary['churn_rate_pct'],
        color=colors[:len(summary)],
        width=0.5,
        edgecolor='white',
        linewidth=1.5
    )

    # Annotate bars with exact values and counts
    for bar, row in zip(bars, summary.itertuples()):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + 0.5,
            f"{row.churn_rate_pct:.1f}%\n({row.churned:,} / {row.total:,})",
            ha='center', va='bottom', fontsize=11, fontweight='bold'
        )

    # Industry benchmark line
    ax.axhline(y=7, color=COLORS['dark'], linestyle='--', linewidth=1.5, alpha=0.7)
    ax.text(2.4, 7.5, "Industry benchmark (7%)", fontsize=9, color=COLORS['dark'], alpha=0.8)

    ax.set_title("Churn Rate by Contract Type\nMonth-to-month customers churn at 15× the rate of two-year contracts")
    ax.set_ylabel("Churn Rate (%)")
    ax.set_xlabel("Contract Type")
    ax.set_ylim(0, summary['churn_rate_pct'].max() * 1.25)
    fig.tight_layout()
    _save(fig, '02_churn_by_contract')
    return fig


def plot_tenure_distribution(df: pd.DataFrame) -> plt.Figure:
    """
    KDE plot comparing tenure distribution for churned vs retained customers.
    Shows that new customers are most at risk.
    """
    fig, ax = plt.subplots(figsize=(10, 6))

    for flag, label, color in [(0, 'Retained', COLORS['retained']), (1, 'Churned', COLORS['churn'])]:
        subset = df[df['churn_flag'] == flag]['tenure']
        subset.plot.kde(ax=ax, label=f"{label} (n={len(subset):,})", color=color, linewidth=2.5)
        ax.axvline(subset.median(), color=color, linestyle='--', linewidth=1, alpha=0.7)
        ax.text(
            subset.median(), ax.get_ylim()[1] * 0.02,
            f"Median: {subset.median():.0f}m",
            color=color, fontsize=9, ha='center'
        )

    ax.set_title("Tenure Distribution: Churned vs Retained Customers\nChurned customers have significantly shorter tenure")
    ax.set_xlabel("Customer Tenure (Months)")
    ax.set_ylabel("Density")
    ax.legend(fontsize=12)
    ax.set_xlim(0, 75)
    fig.tight_layout()
    _save(fig, '03_tenure_distribution_kde')
    return fig


def plot_monthly_charges_vs_churn(df: pd.DataFrame) -> plt.Figure:
    """
    Violin plot: monthly charges distribution by churn status.
    Reveals whether high-paying or low-paying customers churn more.
    """
    fig, ax = plt.subplots(figsize=(9, 6))

    plot_df = df.copy()
    plot_df['Status'] = plot_df['churn_flag'].map({0: 'Retained', 1: 'Churned'})

    sns.violinplot(
        data=plot_df,
        x='Status',
        y='monthly_charges',
        palette={'Retained': COLORS['retained'], 'Churned': COLORS['churn']},
        inner='box',
        ax=ax
    )

    # Add median labels
    for i, (flag, label) in enumerate([(0, 'Retained'), (1, 'Churned')]):
        median = df[df['churn_flag'] == flag]['monthly_charges'].median()
        ax.text(i, median + 2, f"${median:.0f}/mo", ha='center', fontweight='bold', fontsize=11)

    ax.set_title("Monthly Charges Distribution by Churn Status\nChurned customers tend to pay higher monthly fees")
    ax.set_ylabel("Monthly Charges ($)")
    ax.set_xlabel("")
    fig.tight_layout()
    _save(fig, '04_monthly_charges_violin')
    return fig


def plot_churn_heatmap(df: pd.DataFrame) -> plt.Figure:
    """
    Heatmap: churn rate by contract type × internet service.
    Reveals highest-risk customer combinations.
    """
    pivot = df.groupby(['contract', 'internet_service'])['churn_flag'].mean().unstack() * 100

    fig, ax = plt.subplots(figsize=(9, 5))
    sns.heatmap(
        pivot,
        annot=True,
        fmt='.1f',
        cmap='RdYlGn_r',
        ax=ax,
        linewidths=0.5,
        linecolor='white',
        annot_kws={'size': 13, 'weight': 'bold'},
        cbar_kws={'label': 'Churn Rate (%)'}
    )
    ax.set_title("Churn Rate (%) by Contract × Internet Service\nMonth-to-month Fiber customers are highest risk")
    ax.set_xlabel("Internet Service")
    ax.set_ylabel("Contract Type")
    fig.tight_layout()
    _save(fig, '05_churn_heatmap_contract_internet')
    return fig


def plot_health_score_distribution(df: pd.DataFrame) -> plt.Figure:
    """
    Histogram of health scores for churned vs retained customers.
    Validates that the health score separates the two groups.
    """
    if 'health_score' not in df.columns:
        print("⚠️  health_score not found — run feature engineering first")
        return None

    fig, ax = plt.subplots(figsize=(10, 6))

    for flag, label, color in [(0, 'Retained', COLORS['retained']), (1, 'Churned', COLORS['churn'])]:
        subset = df[df['churn_flag'] == flag]['health_score']
        ax.hist(subset, bins=20, alpha=0.65, label=f"{label} (n={len(subset):,})",
                color=color, edgecolor='white', linewidth=0.5)

    ax.axvline(40, color='red', linestyle='--', linewidth=2, label='At Risk threshold (40)')
    ax.axvline(70, color='green', linestyle='--', linewidth=2, label='Healthy threshold (70)')

    ax.set_title("Customer Health Score Distribution\nLower scores strongly associated with churn")
    ax.set_xlabel("Health Score (0–100)")
    ax.set_ylabel("Number of Customers")
    ax.legend(fontsize=11)
    fig.tight_layout()
    _save(fig, '06_health_score_distribution')
    return fig


def plot_payment_method_churn(df: pd.DataFrame) -> plt.Figure:
    """
    Horizontal bar chart: churn rate by payment method.
    Electronic check is almost always the highest-risk payment type.
    """
    summary = (
        df.groupby('payment_method')['churn_flag']
        .agg(['mean', 'count'])
        .reset_index()
        .rename(columns={'mean': 'churn_rate', 'count': 'customers'})
    )
    summary['churn_rate_pct'] = summary['churn_rate'] * 100
    summary = summary.sort_values('churn_rate_pct')

    fig, ax = plt.subplots(figsize=(10, 5))
    bar_colors = [COLORS['churn'] if r > 30 else COLORS['neutral']
                  for r in summary['churn_rate_pct']]
    bars = ax.barh(
        summary['payment_method'],
        summary['churn_rate_pct'],
        color=bar_colors,
        height=0.55,
        edgecolor='white'
    )

    for bar, row in zip(bars, summary.itertuples()):
        ax.text(
            bar.get_width() + 0.5,
            bar.get_y() + bar.get_height() / 2,
            f"{row.churn_rate_pct:.1f}% ({row.customers:,} customers)",
            va='center', fontsize=10
        )

    ax.set_title("Churn Rate by Payment Method\nElectronic check customers churn at ~3× the rate of auto-pay customers")
    ax.set_xlabel("Churn Rate (%)")
    ax.set_xlim(0, summary['churn_rate_pct'].max() * 1.35)
    fig.tight_layout()
    _save(fig, '07_churn_by_payment_method')
    return fig


def plot_services_vs_churn(df: pd.DataFrame) -> plt.Figure:
    """
    Line + scatter: churn rate by number of add-on services.
    Demonstrates the stickiness hypothesis.
    """
    summary = (
        df.groupby('num_services')['churn_flag']
        .agg(['mean', 'count'])
        .reset_index()
        .rename(columns={'mean': 'churn_rate', 'count': 'customers'})
    )
    summary['churn_rate_pct'] = summary['churn_rate'] * 100

    fig, ax1 = plt.subplots(figsize=(9, 6))
    ax2 = ax1.twinx()

    ax1.plot(summary['num_services'], summary['churn_rate_pct'],
             color=COLORS['churn'], linewidth=2.5, marker='o', markersize=8, label='Churn Rate')
    ax2.bar(summary['num_services'], summary['customers'],
            alpha=0.25, color=COLORS['neutral'], label='Customer Count')

    for _, row in summary.iterrows():
        ax1.text(row['num_services'], row['churn_rate_pct'] + 1,
                 f"{row['churn_rate_pct']:.0f}%", ha='center', fontsize=9, color=COLORS['churn'])

    ax1.set_title("Churn Rate vs Number of Add-on Services\nMore services = more sticky customers")
    ax1.set_xlabel("Number of Add-on Services")
    ax1.set_ylabel("Churn Rate (%)", color=COLORS['churn'])
    ax2.set_ylabel("Customer Count", color=COLORS['neutral'])
    ax1.set_xticks(range(7))
    fig.tight_layout()
    _save(fig, '08_churn_by_num_services')
    return fig


def generate_all_charts(df: pd.DataFrame) -> None:
    """
    Generate and save all charts in one call.
    Typically run at the end of a notebook or as a batch script.
    """
    print("📊 Generating all charts...\n")
    plot_churn_overview(df)
    plot_churn_by_contract(df)
    plot_tenure_distribution(df)
    plot_monthly_charges_vs_churn(df)
    plot_churn_heatmap(df)
    plot_health_score_distribution(df)
    plot_payment_method_churn(df)
    plot_services_vs_churn(df)
    print(f"\n✅ All charts saved to: {CHART_DIR}")
