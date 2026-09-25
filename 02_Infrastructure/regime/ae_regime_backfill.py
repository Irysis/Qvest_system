#!/usr/bin/env python
"""ae_regime_backfill.py — AE 신호 2004~2007 백필 (도훈 지시 2026-08-08, 1번 안 ①단계).

목적: `ae_regime_signal_ext.parquet` 가 2008-01부터라 현 PG2(2-4, M4∩AE D3 게이트)의
  종목별 캐리어를 2004-02~ 전 기간으로 재구성할 수 없다. 결손 2004~2007(48 결정월)을 채운다.
  실측(2026-08-08): OOS_START_YEAR=2008 은 데이터 한계가 아니라 **하드코딩 상수**다 —
  사용 FRED 피처 7종 전부 2000-01 유효, 학습 하한(len(Wtr)>=200) 역산 시 2003부터 OOS 가능.

★설계 — 기존 행 불변이 구조적으로 보장되는 방식:
  원본 루프에서 `OOS_START_YEAR` 만 2003 으로 낮추면 **기존 224행이 전부 바뀐다**.
  모델 생성 `train_ae(SeqAE(nfeat), ...)` 이 인자 위치라 seed 리셋(train_ae 내부 79행)
  **이전에** 평가되고, 초기화가 전역 RNG 스트림 위치에 의존한다 — 앞에 연도를 끼우면
  2008 의 스트림 위치가 밀린다(착수 전 코드 정독으로 검거, 아홉 번째 예측 반증).
  → 본 스크립트는 **결손 연도(2004~2007)만** 계산하고 기존 행은 바이트 그대로 둔다.
    각 연도 처리 직전에 seed 를 명시 리셋해 연도 간 스트림 독립성도 확보한다
    (원본과 다른 점이며, 그래서 본 백필분은 원본 스트림 재현이 아니라 **독립 재현**이다 —
    어차피 2004~2007 은 원본이 계산한 적이 없으므로 재현할 대상 자체가 없다).

★검증 4중:
  V1 기존 행 불변: 저장 전 기존 224행과 신규 병합본의 교집합 전 컬럼 동일 (parity, fail-closed)
  V2 PIT: 전 신규 행 last_feat_date < decision_date
  V3 경계 연속성: 2008 경계에서 tau 급변 없는지 보고(차단 아님 — 학습표본 증가의 자연 기울기)
  V4 발화율: 신규 구간 fire_seq 비율 보고 (M4_FIRE_RATE 근방 기대)

모델·상수 = 동결 원본(stage_artifacts/WT_D20260718_007/ae_regime_extend.py) verbatim.
  원본은 감사 증거 동결이라 수정 불가(artifact-storage.md ①) — 여기 복제하고 sha 를 기록한다.

★PIT C11 수리 (2026-09-24 · 판정서 V-03 · 결정 PIT-C11-REMEDIATION 안 B · 1단계 코드):
  구 build_panel(:69-83)은 해외 특성을 미국 관측일(라벨)로 붙였다(`merge_asof(on="Date")`) — 한국 d 행에
  미국 d 종가·공표 전 주간값(STLFSI4 +7일·NFCI +6일)이 실렸다. 이제 특성 패널은
  `ae_pit_features.build_pit_panel`(기반 S0 도우미 fred_asof_join · decision_close) 한 경로로만 만든다.
  원/달러는 DEXKOUS(prohibited) 대신 핀의 ECOS 731Y001(`ecos_krw_usd.parquet`) — 결정 PIT-C11-CONVENTIONS ①.
  산출 행에 C11 표식 4열을 붙이고(`aepf.stamp`), **수리 전 판 기존 행과는 섞지 않는다**(기존 행에 표식이
  없으면 중단 — 한 파일에 두 시간축이 공존하면 소비자가 어느 행이 PIT 인지 모른다).
  ⚠관찰(C11 밖 · 수리 안 함): 아래 SeqAE/PointAE 는 동결 원본(LSTM · 8-4 GELU)과 구조가 다르고(GRU · 16-8 ReLU)
    M4_FIRE_RATE 도 0.12 vs 원본 0.126 이다 — 머리말의 'verbatim' 서술과 다르다. 2단계 재산출 전에 확인할 것.

사용:
  .venv_qvest_ml/Scripts/python.exe 02_Infrastructure/regime/ae_regime_backfill.py [--dry-run] [--pin-dir <핀>]
  (기본 핀 r1 은 수리 전 판이라 ECOS 가 없다 → 입력 오류 2. ECOS 를 담은 핀을 --pin-dir 로.)
종료코드: 0 정상 / 1 parity 위반 / 2 입력 오류 / 3 PIT 위반
"""
from __future__ import annotations

import argparse
import hashlib
import os
import sys

import numpy as np
import pandas as pd
import pyarrow.parquet as pq
import torch
import torch.nn as nn

_REGIME_DIR = os.path.dirname(os.path.abspath(__file__))
if _REGIME_DIR not in sys.path:
    sys.path.insert(0, _REGIME_DIR)
import ae_pit_features as aepf  # noqa: E402  (C11 가용시점 결합 — 해외 특성의 유일한 결합 경로)

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot").replace("\\", "/")
os.chdir(ROOT)
torch.set_num_threads(1)

# ── 동결 원본과 동일 상수 (변경 금지 — 모델 정합) ─────────────────────────────
SEED = 20260718
PIN = ".cache/pins/WT-D20260718_007_r1"
FRED = os.path.join(PIN, "fred_macro_wide.parquet")
BENCH = os.path.join(PIN, "benchmark.parquet")
CARRIER = os.path.join(PIN, "carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet")
ECOS = os.path.join(PIN, aepf.ECOS_KRW_FILE)   # C11: 원/달러 원천(DEXKOUS prohibited)
OUT = "stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet"
SRC_FROZEN = "stage_artifacts/WT_D20260718_007/ae_regime_extend.py"

L = 60; FWD = 21; SMOOTH = 21
STRIDE = 3
D_HID = 16; D_LAT = 8; DROPOUT = 0.1
EPOCHS = 25; LR = 1e-3; WD = 1e-4; PATIENCE = 4; BATCH = 256
M4_FIRE_RATE = 0.12
FRED_FEATS = ["VIX", "Term_Spread", "KRW_USD", "US_10Y_Yield", "US_2Y_Yield",
              "StL_Fin_Stress", "Chi_Fin_Cond"]

BACKFILL_YEARS = [2004, 2005, 2006, 2007]   # 결손 연도만. 기존 행은 절대 재계산하지 않는다.


def build_panel():
    """★C11: 해외 특성은 가용일로 결합한다(ae_pit_features — S0 도우미 경유). 반환형은 구판과 같다."""
    return aepf.build_pit_panel(FRED, BENCH, ECOS, FRED_FEATS)


class SeqAE(nn.Module):
    def __init__(self, nfeat):
        super().__init__()
        self.enc = nn.GRU(nfeat, D_HID, batch_first=True)
        self.lat = nn.Linear(D_HID, D_LAT)
        self.dec_in = nn.Linear(D_LAT, D_HID)
        self.dec = nn.GRU(D_HID, D_HID, batch_first=True)
        self.out = nn.Linear(D_HID, nfeat)
        self.drop = nn.Dropout(DROPOUT)

    def forward(self, x):
        _, h = self.enc(x)
        z = self.lat(self.drop(h[-1]))
        d = self.dec_in(z).unsqueeze(1).repeat(1, x.size(1), 1)
        y, _ = self.dec(d)
        return self.out(y)


class PointAE(nn.Module):
    def __init__(self, nfeat):
        super().__init__()
        self.net = nn.Sequential(nn.Linear(nfeat, D_HID), nn.ReLU(), nn.Dropout(DROPOUT),
                                 nn.Linear(D_HID, D_LAT), nn.ReLU(),
                                 nn.Linear(D_LAT, D_HID), nn.ReLU(),
                                 nn.Linear(D_HID, nfeat))

    def forward(self, x): return self.net(x)


def make_seq_windows(end_idx_list, X):
    ws = [X[i - L + 1:i + 1] for i in end_idx_list if i - L + 1 >= 0]
    if not ws: return None, None
    return np.stack(ws).astype(np.float32), end_idx_list


def train_ae(model, Xtr, Xva, is_seq):
    torch.manual_seed(SEED); np.random.seed(SEED)
    lossf = nn.MSELoss()
    opt = torch.optim.Adam(model.parameters(), lr=LR, weight_decay=WD)
    Xtr_t = torch.tensor(Xtr); Xva_t = torch.tensor(Xva)
    n = len(Xtr_t); best = np.inf; bad = 0; best_state = None
    for ep in range(EPOCHS):
        model.train(); perm = torch.randperm(n)
        for b in range(0, n, BATCH):
            idx = perm[b:b + BATCH]
            opt.zero_grad(); loss = lossf(model(Xtr_t[idx]), Xtr_t[idx]); loss.backward(); opt.step()
        model.eval()
        with torch.no_grad(): vl = lossf(model(Xva_t), Xva_t).item()
        if vl < best - 1e-6: best = vl; bad = 0; best_state = {k: v.clone() for k, v in model.state_dict().items()}
        else:
            bad += 1
            if bad >= PATIENCE: break
    if best_state: model.load_state_dict(best_state)
    model.eval(); return model


def recon_err_seq(model, W):
    with torch.no_grad():
        t = torch.tensor(W.astype(np.float32)); r = model(t)
        return ((r - t) ** 2).mean(dim=(1, 2)).numpy()


def recon_err_point(model, V):
    with torch.no_grad():
        t = torch.tensor(V.astype(np.float32)); r = model(t)
        return ((r - t) ** 2).mean(dim=1).numpy()


def die(code, msg):
    print(f"[backfill:FATAL] {msg}"); sys.exit(code)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--pin-dir", default=None,
                    help="핀 디렉토리(기본 r1). ★C11 이후 핀에 ecos_krw_usd.parquet 가 있어야 한다")
    args = ap.parse_args()
    if args.pin_dir:
        global PIN, FRED, BENCH, CARRIER, ECOS
        PIN = args.pin_dir
        FRED = os.path.join(PIN, "fred_macro_wide.parquet")
        BENCH = os.path.join(PIN, "benchmark.parquet")
        CARRIER = os.path.join(PIN, "carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet")
        ECOS = os.path.join(PIN, aepf.ECOS_KRW_FILE)

    for p in (FRED, BENCH, CARRIER, OUT, SRC_FROZEN, ECOS):
        if not os.path.exists(p):
            die(2, f"입력 부재: {p}" + (" — C11 이후 원/달러 = 핀의 ECOS 731Y001(DEXKOUS prohibited). "
                                         "수리 전 핀이다: ECOS 를 담은 핀을 --pin-dir 로" if p == ECOS else ""))
    src_sha = hashlib.sha1(open(SRC_FROZEN, "rb").read()).hexdigest()
    print(f"[backfill] 동결 원본 sha1={src_sha[:12]} (모델·상수 verbatim 복제 근거)")

    existing = pq.read_table(OUT).to_pandas()
    existing["decision_date"] = pd.to_datetime(existing["decision_date"])
    n_exist = len(existing)
    exist_min = existing["decision_date"].min()
    print(f"[backfill] 기존 {n_exist}행 {exist_min.date()} ~ {existing['decision_date'].max().date()}")
    if exist_min <= pd.Timestamp("2004-12-31"):
        die(2, "기존 패널이 이미 2004 를 포함 — 백필 대상 없음(중복 실행 방지)")
    # ★C11: 수리 판 백필을 수리 전 판 기존 행 옆에 붙이지 않는다(한 파일 두 시간축 금지)
    if not aepf.is_c11_stamped(existing):
        die(2, "기존 행에 C11 표식이 없다(수리 전 판 — 해외 특성 관측일 결합·DEXKOUS). 수리 판 백필을 섞지 않는다 — "
               "기존 행을 먼저 C11 판으로 재산출할 것(ae_regime_monthly.py · 2단계 결정 PIT-C11-BOOK0001)")

    try:
        panel, feat_cols = build_panel()
    except aepf.AEPitError as e:
        die(3 if "★C11" in str(e) else 2, str(e))
    nfeat = len(feat_cols)
    Xraw = panel[feat_cols].values.astype(np.float64)
    panel_dates = pd.to_datetime(panel["Date"]).values
    print(f"[panel] rows={len(panel)} feats={nfeat} range {str(panel['Date'].min())[:10]}..{str(panel['Date'].max())[:10]}")

    car = pq.read_table(CARRIER).to_pandas()
    dec = pd.to_datetime(car["decision_date"]).drop_duplicates().sort_values().reset_index(drop=True)
    dec = dec[(dec.dt.year >= min(BACKFILL_YEARS)) & (dec.dt.year <= max(BACKFILL_YEARS))]
    # 결정일 원천 주의: 2-1 캐리어를 쓰지만 여기서 소비하는 건 **월초 결정일 격자뿐**이다
    # (점수·비중·보유는 일절 안 읽는다). 격자는 캘린더 산물이라 PG2 정체성과 무관.
    print(f"[decisions] 백필 대상 n={len(dec)} {str(dec.min())[:10]}..{str(dec.max())[:10]}")
    if not len(dec): die(2, "백필 결정일 0건")

    rows = []
    for year in BACKFILL_YEARS:
        # ★연도별 독립 seed 리셋 — 원본과 달리 스트림 위치 의존을 없앤다.
        #   (원본은 모델 생성이 train_ae 인자라 seed 리셋 *전*에 초기화됨 → 루프 순서가
        #    결과에 영향. 그 구조 때문에 OOS_START_YEAR 하향만으로는 기존 행이 바뀐다.)
        torch.manual_seed(SEED + year); np.random.seed(SEED + year)
        boundary = np.datetime64(f"{year}-01-01")
        tr_idx = np.where(panel_dates < boundary)[0]
        if len(tr_idx) < 500:
            print(f"[refit {year}] 학습일 {len(tr_idx)} < 500 — 건너뜀(해당 연도 결정월은 fire=0 규약으로 남음)")
            continue
        mu = Xraw[tr_idx].mean(0); sd = Xraw[tr_idx].std(0); sd[sd < 1e-8] = 1.0
        Xz = ((Xraw - mu) / sd).astype(np.float32)
        seq_end_all = [i for i in tr_idx if i - L + 1 >= 0]
        seq_end_tr = seq_end_all[::STRIDE]
        Wtr, _ = make_seq_windows(seq_end_tr, Xz)
        Vtr = Xz[tr_idx]
        if Wtr is None or len(Wtr) < 200:
            print(f"[refit {year}] 시퀀스창 부족 — 건너뜀"); continue
        cut = np.datetime64(f"{year - 1}-01-01")
        fit_end = [i for i in seq_end_tr if panel_dates[i] < cut]
        val_end = [i for i in seq_end_tr if panel_dates[i] >= cut]
        if len(val_end) < 30 or len(fit_end) < 200:
            k = int(len(seq_end_tr) * 0.85); fit_end = seq_end_tr[:k]; val_end = seq_end_tr[k:]
        Wfit, _ = make_seq_windows(fit_end, Xz); Wval, _ = make_seq_windows(val_end, Xz)
        Vfit = Xz[[i for i in tr_idx if panel_dates[i] < cut]]
        Vval = Xz[[i for i in tr_idx if panel_dates[i] >= cut]]
        if len(Vval) < 40:
            Vfit = Vtr[:int(len(Vtr) * 0.85)]; Vval = Vtr[int(len(Vtr) * 0.85):]
        seq_ae = train_ae(SeqAE(nfeat), Wfit, Wval, True)
        pt_ae = train_ae(PointAE(nfeat), Vfit, Vval, False)
        e_seq_is = recon_err_seq(seq_ae, Wtr)
        e_pt_daily = recon_err_point(pt_ae, Xz)

        def pt_score_at(end_i):
            lo = max(0, end_i - SMOOTH + 1); return float(np.mean(e_pt_daily[lo:end_i + 1]))
        e_pt_is = np.array([pt_score_at(i) for i in tr_idx if i >= SMOOTH - 1])
        tau_seq = float(np.quantile(e_seq_is, 1.0 - M4_FIRE_RATE))
        tau_pt = float(np.quantile(e_pt_is, 1.0 - M4_FIRE_RATE))
        yr_dec = dec[dec.dt.year == year]
        for d in yr_dec:
            dd = np.datetime64(pd.Timestamp(d)); valid = np.where(panel_dates < dd)[0]
            if len(valid) < L: continue
            end = valid[-1]
            s_seq = float(recon_err_seq(seq_ae, Xz[end - L + 1:end + 1][None, :, :])[0])
            s_pt = pt_score_at(end)
            dd_loose = dd + np.timedelta64(FWD * 7 // 5, "D")
            vl = np.where(panel_dates < dd_loose)[0]
            if len(vl) >= L:
                el = vl[-1]
                s_seq_l = float(recon_err_seq(seq_ae, Xz[el - L + 1:el + 1][None, :, :])[0])
                s_pt_l = pt_score_at(el); lfd_l = pd.Timestamp(panel_dates[el])
            else:
                s_seq_l = np.nan; s_pt_l = np.nan; lfd_l = pd.NaT
            rows.append(dict(decision_date=pd.Timestamp(d), model_year=year,
                             ae_seq=s_seq, ae_pt=s_pt, tau_seq=tau_seq, tau_pt=tau_pt,
                             fire_seq=int(s_seq > tau_seq), fire_pt=int(s_pt > tau_pt),
                             last_feat_date=pd.Timestamp(panel_dates[end]),
                             ae_seq_loose=s_seq_l, ae_pt_loose=s_pt_l,
                             fire_seq_loose=int(s_seq_l > tau_seq) if np.isfinite(s_seq_l) else 0,
                             fire_pt_loose=int(s_pt_l > tau_pt) if np.isfinite(s_pt_l) else 0,
                             last_feat_date_loose=lfd_l))
        print(f"[refit {year}] train_days={len(tr_idx)} tau_seq={tau_seq:.4f} tau_pt={tau_pt:.4f} scored={len(yr_dec)}")

    if not rows: die(2, "백필 산출 0행")
    new = pd.DataFrame(rows).sort_values("decision_date").reset_index(drop=True)

    # ── V2 PIT ────────────────────────────────────────────────────────────────
    bad = int((pd.to_datetime(new["last_feat_date"]) >= pd.to_datetime(new["decision_date"])).sum())
    if bad: die(3, f"PIT 위반 {bad}행 (last_feat_date >= decision_date)")
    # ★C11 표식 + 검사: 창에 실린 해외 관측 가용일 ≤ last_feat_date < decision_date
    try:
        new = aepf.stamp(new, panel, aepf.rules_regime_key())
    except aepf.AEPitError as e:
        die(3, str(e))
    print(f"[V2 PIT] 신규 {len(new)}행 전부 last_feat < decision OK · C11 표식 {aepf.FEAT_JOIN}")

    # ── V1 기존 행 불변 (구조 보장이지만 그래도 **잰다** — 주장과 확인은 다르다) ──
    merged = pd.concat([new, existing], ignore_index=True).sort_values("decision_date").reset_index(drop=True)
    re_read = merged[merged["decision_date"].isin(existing["decision_date"])]
    chk_cols = [c for c in existing.columns if c in re_read.columns]
    a = existing.sort_values("decision_date")[chk_cols].reset_index(drop=True)
    b = re_read.sort_values("decision_date")[chk_cols].reset_index(drop=True)
    if len(a) != len(b) or not a.equals(b):
        die(1, f"parity 위반 — 기존 {len(a)}행 vs 병합 후 {len(b)}행 동일성 실패")
    print(f"[V1 parity] 기존 {len(a)}행 바이트-수준 불변 OK")

    # ── V3 경계 연속성 (보고만) ───────────────────────────────────────────────
    t07 = new[new["model_year"] == 2007]["tau_seq"].iloc[0] if (new["model_year"] == 2007).any() else np.nan
    t08 = existing.sort_values("decision_date")["tau_seq"].iloc[0]
    print(f"[V3 경계] tau_seq 2007(백필)={t07:.4f} vs 2008(기존)={t08:.4f} "
          f"(학습표본 증가의 자연 기울기 — 급변이면 육안 확인 필요)")

    # ── V4 발화율 (보고만) ────────────────────────────────────────────────────
    fr_new = new["fire_seq"].mean(); fr_old = existing["fire_seq"].mean()
    print(f"[V4 발화율] 백필 구간 fire_seq={fr_new:.3f} (기존 {fr_old:.3f}, 설계 {M4_FIRE_RATE})")

    if args.dry_run:
        print(f"[backfill] DRY-RUN — 저장 생략. 병합 시 {len(merged)}행 "
              f"({merged['decision_date'].min().date()} ~ {merged['decision_date'].max().date()})")
        return

    bak = OUT + f".bak_pre_backfill_20260808"
    if not os.path.exists(bak):
        import shutil; shutil.copy2(OUT, bak)
        print(f"[backfill] 원본 백업: {bak}")
    merged.to_parquet(OUT, index=False)
    print(f"[backfill] 저장 {OUT} — {len(merged)}행 "
          f"({merged['decision_date'].min().date()} ~ {merged['decision_date'].max().date()})")


if __name__ == "__main__":
    main()
