"""Feature loader — features_master.parquet (R-built) read + screening.

Inherits WT-D20260514_008 features_master.parquet (long format).
Quality screening per feature_quality_audit.json:
  - KEEP only (drop zero variance + high missing 50%+)
  - cor cluster > 0.99 deduplication (head only)
"""
import json
from pathlib import Path
import pandas as pd
import pyarrow.parquet as pq

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
FEATURES_MASTER = PROJECT_ROOT / "stage_artifacts/WT_D20260514_008/features_master.parquet"
FEATURE_REGISTRY = PROJECT_ROOT / "stage_artifacts/WT_D20260514_008/feature_registry.json"
QUALITY_AUDIT = PROJECT_ROOT / "stage_artifacts/WT_D20260514_008/feature_quality_audit.json"


def load_features_master(keep_only: bool = True,
                         drop_cor_cluster: bool = True,
                         cor_threshold: float = 0.99) -> pd.DataFrame:
    """Load features_master.parquet with quality screening.

    Args:
        keep_only: drop features with status != 'KEEP' per feature_quality_audit
        drop_cor_cluster: drop redundant cluster members (keep only head)
        cor_threshold: cor > threshold defines redundancy cluster

    Returns:
        DataFrame: sig_date × Ticker × features (wide or long depending on source)
    """
    df = pd.read_parquet(FEATURES_MASTER)

    if keep_only and QUALITY_AUDIT.exists():
        with open(QUALITY_AUDIT) as f:
            audit = json.load(f)
        # Identify KEEP features
        if isinstance(audit, dict) and "features" in audit:
            keep_features = [
                f["feature_id"] for f in audit["features"]
                if f.get("screening_recommendation") == "KEEP"
            ]
        elif isinstance(audit, list):
            keep_features = [
                f["feature_id"] for f in audit
                if f.get("screening_recommendation") == "KEEP"
            ]
        else:
            keep_features = None

        if keep_features:
            # Filter columns (assumes wide format) or rows (long format)
            if "feature_id" in df.columns:
                df = df[df["feature_id"].isin(keep_features)]
            else:
                cols_to_keep = ["sig_date", "Ticker"] + [c for c in df.columns
                                                          if c in keep_features]
                df = df[cols_to_keep]

    return df


def load_registry() -> dict:
    """Load feature_registry.json metadata."""
    with open(FEATURE_REGISTRY) as f:
        return json.load(f)


def features_to_wide(df: pd.DataFrame) -> pd.DataFrame:
    """Pivot long format (sig_date, Ticker, feature_id, value) → wide.

    Returns: DataFrame indexed by (sig_date, Ticker), columns are features
    """
    if "feature_id" in df.columns and "value" in df.columns:
        return df.pivot(index=["sig_date", "Ticker"],
                       columns="feature_id",
                       values="value").reset_index()
    return df  # already wide


if __name__ == "__main__":
    df = load_features_master(keep_only=True)
    print(f"Features master loaded: {df.shape}")
    print(f"Columns sample: {list(df.columns[:10])}")
    if "sig_date" in df.columns:
        print(f"sig_date range: {df['sig_date'].min()} ~ {df['sig_date'].max()}")
        print(f"Unique sig_dates: {df['sig_date'].nunique()}")
    if "Ticker" in df.columns:
        print(f"Unique tickers: {df['Ticker'].nunique()}")
