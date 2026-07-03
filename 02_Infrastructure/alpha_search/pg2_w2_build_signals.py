# pg2_w2_build_signals.py — PG2 강화 P1: earnings@3M lead 정제 신호 3종 + 보유밴드 입력 패널 구성
#
# 목적(도훈 지시 2026-07-02, 04_Research/pg2_reinforcement_roadmap_20260702.md P1):
#   내부 earnings@3M lead(SUE/ESBR/ESCR/TP_gap/Composite family)를 논문-근거 정제 신호 3종으로
#   강화하고, 각 composite에 보유밴드 A/B를 실측하기 위한 월간 패널을 만든다.
#   측정(SR/CAGR/MDD/PORT_t) 헤드라인은 R canonical_screen_bt(계약)에서 나오며, 본 스크립트는
#   신호 *구성*(scores)과 진단 IC/IR만 산출한다(proxy 손계산 금지 원칙 — 진단만).
#
# ★정직 라벨(task honesty gate): 애널리스트 개인(브로커)-레벨 데이터 없음.
#   → 3 신호 전부 **컨센서스-레벨 충실 사상**(consensus-level faithful mapping)으로 명시 라벨.
#   batch_434 가드: 논문이 기술하지 않은 신호는 날조하지 않는다. 아래는 전부 논문 메커니즘의
#   컨센서스-데이터 사상이며, 데이터가 못 미치는 항목은 skip + 사유 기록.
#
# PIT 규율:
#   - 결정월 t(ym)의 신호 = factor_db_{ym}.parquet(=ym말 스냅샷, Z_Score/Z_Sector/Raw_Value/Rank_Pct).
#   - 시리얼 리비전 streak = 스냅샷 t, t-1, t-2, ...(전부 ≤ t) 만 사용 → 미래참조 없음.
#   - forward 1M 실현수익 = RAWDATA 복리, ym+1 (assemble_phase0.py와 동일 규약).
#   - lag1 스트레스: 신호를 한 달 추가 지연(t-1 스냅샷을 t 결정에 사용)한 변형도 산출 → 동월 누출 자가검증.
#   - 유니버스: RAWDATA K200|KQ150 시변 멤버십(PIT), 유동성 20d ADV>=2e8(t-1).
#
# 산출: stage_artifacts/pg2_w2_earnings3m/panel_signals.parquet (R 소비)
#       + build_meta.json (구성 사유·streak 윈도우·n_trials 로그의 신호부)
import pyarrow.parquet as pq
import pandas as pd, numpy as np, os, json, glob, sys, io, datetime

ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CACHE = ROOT + "/.cache"
FDB = CACHE + "/factor_db"
OUTDIR = ROOT + "/stage_artifacts/pg2_w2_earnings3m"
os.makedirs(OUTDIR, exist_ok=True)
LOG = io.StringIO()
def log(s):
    print(s, flush=True); LOG.write(str(s) + "\n")

START = "2005-01"; END = "2026-06"   # 표준 백테 기간(2005-01~), 스냅샷 존재 범위 내
STREAK_WIN = 6        # 리비전 시리얼 모멘텀 streak 관찰 윈도우(월) — 사전 고정(chain 규약)
DISP_WIN = 12         # 리비전 크기 trailing dispersion 윈도우(월) — 사전 고정
LIQ_MIN = 2e8

def yms(s, e):
    return pd.date_range(s + "-01", e + "-01", freq="MS").strftime("%Y-%m").tolist()

# ---------------------------------------------------------------------------
# 1) 월간 factor_db 스냅샷 로드 — earnings family 컨센서스 팩터의 Raw/Z/Z_Sector
#    Raw_Value: winsorize(1%,99%) 후 사용(C05/C06 raw 극단값 존재 — inspect 실증).
# ---------------------------------------------------------------------------
FAM = ["C01_SUE", "C02_EPS_Chg_1m", "C03_EPS_Chg_3m", "C04_ESBR", "C05_ESCR",
       "C06_TP_Gap", "C07_TP_Mom", "C12_Estimate_Dispersion_Proxy", "C19_Composite_Earnings"]

def load_snapshot(ym):
    fp = FDB + f"/factor_db_{ym.replace('-','')}.parquet"
    if not os.path.exists(fp):
        return None
    t = pq.read_table(fp, columns=["Ticker", "Factor_Name", "Raw_Value", "Z_Score",
                                    "Z_Sector", "Rank_Pct", "Coverage"]).to_pandas()
    t = t[(t["Coverage"] == True) & (t["Factor_Name"].isin(FAM))]
    if len(t) == 0:
        return None
    t["ym"] = ym
    return t

months = yms(START, END)
snaps = []
for ym in months:
    s = load_snapshot(ym)
    if s is not None:
        snaps.append(s)
snap = pd.concat(snaps, ignore_index=True)
log(f"[1] snapshots loaded: months={snap['ym'].nunique()} rows={len(snap)}")

def winsor(x, lo=0.01, hi=0.99):
    ql, qh = x.quantile(lo), x.quantile(hi)
    return x.clip(ql, qh)

# per (ym, factor) winsorize raw; keep Z_Score / Z_Sector as-is (이미 표준화, PIT-clean)
snap["Raw_w"] = snap.groupby(["ym", "Factor_Name"])["Raw_Value"].transform(winsor)

# wide pivots
def pivot(val, suffix):
    w = snap.pivot_table(index=["ym", "Ticker"], columns="Factor_Name", values=val, aggfunc="first")
    w.columns = [f"{c}__{suffix}" for c in w.columns]
    return w
W = pd.concat([pivot("Z_Score", "z"), pivot("Z_Sector", "zsec"), pivot("Raw_w", "raw"),
               pivot("Rank_Pct", "rk")], axis=1).reset_index()
log(f"[1] wide panel: {W.shape}")

# ---------------------------------------------------------------------------
# 2) 정제 신호 3종 구성 (컨센서스-레벨 충실 사상 — 개인레벨 데이터 없음, 명시 라벨)
# ---------------------------------------------------------------------------
W = W.sort_values(["Ticker", "ym"]).reset_index(drop=True)

# --- Signal 1: 혁신 리비전 분리 (Gleason-Lee 2003 + JBFA revision momentum) ---
#   컨센서스-레벨 사상:
#   (a) 리비전 시리얼 모멘텀: 최근 STREAK_WIN개월 EPS revision(C02 raw) 부호가 연속 동방향인 streak를
#       크기 가중(부호 일관 streak 길이 × 최근 리비전 z). 개인 애널리스트 streak 대신 컨센서스 시계열 streak.
#   (b) 리비전 크기의 trailing dispersion 대비 z(innovation): |Δ컨센서스|를 자기 종목 trailing DISP_WIN
#       변동으로 표준화 — herding(작은 반복 조정) 대비 혁신(큰 이탈) 분리. Gleason-Lee "innovation" 사상.
rev = "C02_EPS_Chg_1m__raw"    # 월간 EPS 컨센서스 리비전 raw (부호=방향)
def serial_streak(g):
    s = np.sign(g[rev].fillna(0).values)
    out = np.zeros(len(s))
    run = 0; prevsign = 0
    for i in range(len(s)):
        if s[i] != 0 and s[i] == prevsign:
            run += 1
        elif s[i] != 0:
            run = 1
        else:
            run = 0
        out[i] = s[i] * run   # 부호 × 연속길이
        prevsign = s[i] if s[i] != 0 else prevsign
    return pd.Series(out, index=g.index)
W["rev_streak"] = W.groupby("Ticker", group_keys=False).apply(serial_streak)
# trailing 통계는 shift(1)로 당월 raw 제외(순수 과거) 후 rolling — C1/C2 정합
def trail_innov(g):
    r = g[rev]
    mu = r.shift(1).rolling(DISP_WIN, min_periods=4).mean()
    sd = r.shift(1).rolling(DISP_WIN, min_periods=4).std()
    return (r - mu) / sd.replace(0, np.nan)
W["rev_innov"] = W.groupby("Ticker", group_keys=False).apply(trail_innov)
#   최종 S1 = 혁신 상향 리비전만(herding 제거). 시리얼 streak(양의 동방향) × innovation z 결합.
#   두 성분 각각 월별 횡단면 z 후 평균(혁신도 conditioning). raw NA→0.
def xs_z(col):
    return W.groupby("ym")[col].transform(lambda s: (s - s.mean()) / s.std(ddof=0) if s.std(ddof=0) > 0 else s * 0)
W["S1_innovrev"] = 0.5 * xs_z("rev_streak") + 0.5 * xs_z("rev_innov")

# --- Signal 2: TP implied return 섹터內 상대화 (Da-Schaumburg 2011) ---
#   충실 사상: TP_gap의 섹터-중립 표준화 = factor_db Z_Sector(C06). 이미 WICS 섹터內 z(PIT 스냅샷).
#   Da-Schaumburg 핵심: raw TPER 정렬=베타 정렬 노이즈 → 섹터내 상대서열만 유효. Z_Sector가 정확 대응.
W["S2_tpsect"] = W["C06_TP_Gap__zsec"]

# --- Signal 3: 3-신호 합의 (2012 JPM) ---
#   충실 사상(가용 필드 내): EPS revision(C02/C03) × ESBR 추천계열(C04) × TP revision(C07_TP_Mom) 동방향 합의.
#   투자의견(recommendation) 원 시트는 미보유 → ESBR(% 상향 breadth)을 추천계열 대리로 명시 사용(정직 라벨).
#   합의 스코어 = 부호 일치도(2-of-3 / 3-of-3) 가중 + 강도. herding·상충 신호 제거.
def sgn(col):
    return np.sign(W[col].fillna(0))
s_eps = sgn("C03_EPS_Chg_3m__raw")     # 3M EPS 리비전 방향(3M horizon 정합)
s_esbr = sgn("C04_ESBR__z")            # 추천계열 대리(상향 breadth) 방향
s_tp = sgn("C07_TP_Mom__raw")          # TP 리비전 방향
agree = s_eps + s_esbr + s_tp          # -3..+3 동방향 합의 count
# 강도 결합: 합의 부호 × (개별 z 크기 평균). 합의 없으면(=0) 중립.
mag = (W["C03_EPS_Chg_3m__z"].fillna(0).abs()
       + W["C04_ESBR__z"].fillna(0).abs()
       + W["C07_TP_Mom__zsec"].fillna(0).abs()) / 3.0
W["S3_consensus"] = np.sign(agree) * (agree.abs() / 3.0) * mag
W["S3_agree_count"] = agree

# --- Baseline: 내부 earnings@3M family broad composite (Round7/8 정의 재현) ---
#   EARNB = z(C01,C02,C04,C05,C06,C19) 등가 — 패널 Z_Score 평균. paired 비교 기준.
BASE_MEMBERS = ["C01_SUE__z", "C02_EPS_Chg_1m__z", "C04_ESBR__z",
                "C05_ESCR__z", "C06_TP_Gap__z", "C19_Composite_Earnings__z"]
avail_base = [c for c in BASE_MEMBERS if c in W.columns]
W["BASE_earn3m"] = W[avail_base].mean(axis=1, skipna=True)
log(f"[2] baseline members used: {avail_base}")

# --- Composites: 정제 신호를 baseline에 결합한 강화판 ---
#   COMP_S1: baseline + S1(혁신 리비전) 필터-결합
#   COMP_S2: baseline의 TP_gap 슬롯을 S2(섹터상대)로 치환 (Da-Schaumburg 처방)
#   COMP_S3: baseline + S3(합의) 결합
#   COMP_ALL: 3종 전부 결합
W["COMP_S1"] = W[["BASE_earn3m", "S1_innovrev"]].mean(axis=1, skipna=True)
base_noTP = [c for c in avail_base if c != "C06_TP_Gap__z"]
W["COMP_S2"] = W[base_noTP + ["S2_tpsect"]].mean(axis=1, skipna=True)
W["COMP_S3"] = W[["BASE_earn3m", "S3_consensus"]].mean(axis=1, skipna=True)
W["COMP_ALL"] = W[["BASE_earn3m", "S1_innovrev", "S2_tpsect", "S3_consensus"]].mean(axis=1, skipna=True)

SIG_COLS = ["BASE_earn3m", "S1_innovrev", "S2_tpsect", "S3_consensus",
            "COMP_S1", "COMP_S2", "COMP_S3", "COMP_ALL"]

# ---------------------------------------------------------------------------
# 3) 유니버스(K200|KQ150 시변) + 유동성(t-1 20d ADV) + forward 1M 수익 + 벤치
# ---------------------------------------------------------------------------
rd = pq.read_table(CACHE + "/RAWDATA.parquet",
                   columns=["Date", "Ticker", "Ret", "Close", "Vol", "K200", "KQ150"]).to_pandas()
rd["ym"] = pd.to_datetime(rd["Date"]).dt.strftime("%Y-%m")
rd = rd.dropna(subset=["Ret"])
rd["lr"] = np.log1p(rd["Ret"].clip(lower=-0.99))
rd["tv"] = rd["Close"] * rd["Vol"]
# 월간 집계: forward 1M 수익 + 유니버스 멤버십(월내 any) + 20d ADV(월말 근사=월평균 거래대금)
g = rd.sort_values(["Ticker", "Date"]).groupby(["Ticker", "ym"])
mm = g.agg(lr=("lr", "sum"),
           k200=("K200", "max"), kq150=("KQ150", "max"),
           adv=("tv", "mean")).reset_index()
mm["mret"] = np.expm1(mm["lr"])
mm = mm.sort_values(["Ticker", "ym"])
mm["fwd_ret_1m"] = mm.groupby("Ticker")["mret"].shift(-1)     # t → t+1 forward
mm["adv_lag1"] = mm.groupby("Ticker")["adv"].shift(1)          # t-1 ADV (C10 PIT)
mm["in_univ"] = ((mm["k200"].fillna(0) > 0) | (mm["kq150"].fillna(0) > 0)).astype(int)

panel = W.merge(mm[["Ticker", "ym", "fwd_ret_1m", "adv_lag1", "in_univ"]],
                on=["Ticker", "ym"], how="inner")
panel = panel[panel["in_univ"] == 1].copy()
panel = panel[panel["adv_lag1"].isna() | (panel["adv_lag1"] >= LIQ_MIN)].copy()
log(f"[3] panel after univ+liq: rows={len(panel)} months={panel['ym'].nunique()}")

# lag1 스트레스: 각 신호를 종목별 한 달 추가 지연 → 동월 누출 자가검증용 열
for c in SIG_COLS:
    panel[c + "__lag1"] = panel.groupby("Ticker")[c].shift(1)

# Date(월말) 부여 — R canonical_screen_bt는 Date 키. 스냅샷 ym말 = RAWDATA 해당 ym 마지막 거래일.
eom = rd.groupby("ym")["Date"].max().rename("Date").reset_index()
panel = panel.merge(eom, on="ym", how="left")

# ---------------------------------------------------------------------------
# 4) 진단 IC (Spearman, 신호↔forward 1M) — 진단 전용(헤드라인 아님)
# ---------------------------------------------------------------------------
def ic_diag(col):
    d = panel.dropna(subset=[col, "fwd_ret_1m"])
    ics = d.groupby("ym").apply(lambda gg: gg[col].corr(gg["fwd_ret_1m"], method="spearman")).dropna()
    if len(ics) < 6:
        return dict(n=len(ics))
    def sub(lo, hi):
        x = ics[(ics.index >= lo) & (ics.index <= hi)]
        return round(float(x.mean() / x.std() * np.sqrt(len(x))), 2) if len(x) > 3 else None
    return dict(n=int(len(ics)), ic_mean=round(float(ics.mean()), 4),
                icir=round(float(ics.mean() / ics.std() * np.sqrt(12)), 2),
                t_full=round(float(ics.mean() / ics.std() * np.sqrt(len(ics))), 2),
                hit=round(float((ics > 0).mean()), 2),
                t_2010_15=sub("2010-01", "2015-12"),
                t_2016_20=sub("2016-01", "2020-12"),
                t_2021_26=sub("2021-01", "2026-12"))
ic_report = {c: ic_diag(c) for c in SIG_COLS}
log("[4] IC diagnostics (Spearman, 1M forward, 진단 전용):")
for c, v in ic_report.items():
    log(f"    {c:16s} {v}")

# ---------------------------------------------------------------------------
# 5) 저장
# ---------------------------------------------------------------------------
keep = ["ym", "Date", "Ticker", "fwd_ret_1m", "adv_lag1"] + SIG_COLS + [c + "__lag1" for c in SIG_COLS] + ["S3_agree_count"]
panel[keep].to_parquet(OUTDIR + "/panel_signals.parquet", index=False)
log(f"[5] saved: {OUTDIR}/panel_signals.parquet  cols={len(keep)}")

meta = {
    "date": datetime.datetime.now().isoformat(timespec="seconds"),
    "task": "PG2 강화 P1 — earnings@3M lead 정제(신호 3종 + 보유밴드) 신호구성부",
    "roadmap": "04_Research/pg2_reinforcement_roadmap_20260702.md P1",
    "honesty_label": "브로커(개인 애널리스트)-레벨 데이터 없음 → 3 신호 전부 컨센서스-레벨 충실 사상. 투자의견(recommendation) 원시트 미보유 → S3에서 ESBR(상향 breadth)을 추천계열 대리로 사용(명시).",
    "signals": {
        "S1_innovrev": "혁신 리비전 분리(Gleason-Lee 2003 + JBFA): (a)EPS리비전 시리얼 streak(부호×연속길이) + (b)리비전 크기 innovation z(trailing %d개월 dispersion 대비). herding 제거." % DISP_WIN,
        "S2_tpsect": "TP implied return 섹터내 상대화(Da-Schaumburg 2011): C06_TP_Gap Z_Sector(WICS 섹터중립 z, PIT 스냅샷).",
        "S3_consensus": "3-신호 합의(2012 JPM): EPS리비전(C03)×ESBR추천대리(C04)×TP리비전(C07) 동방향 합의 count×강도.",
        "band": "Blitz et al FAJ 2023 보유밴드 — R 측정단(canonical_screen_bt+band weight)에서 A/B."
    },
    "streak_window_months": STREAK_WIN,
    "dispersion_window_months": DISP_WIN,
    "baseline_members": avail_base,
    "pit_notes": "신호@ym말 스냅샷(≤t), streak/dispersion trailing(shift(1) rolling), forward 1M=ym+1, ADV t-1, 유니버스 K200|KQ150 시변. lag1 스트레스열 동시 산출.",
    "ic_diagnostics_1m_forward": ic_report,
    "n_months": int(panel["ym"].nunique()),
    "n_rows": int(len(panel)),
    "selection_type": "chain",
    "note": "IC는 진단 전용. 헤드라인 SR/CAGR/MDD/PORT_t는 R canonical_screen_bt(계약)에서 산출."
}
json.dump(meta, open(OUTDIR + "/build_meta.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
open(OUTDIR + "/build_log.txt", "w", encoding="utf-8").write(LOG.getvalue())
log("[done] build_meta.json + build_log.txt written")
