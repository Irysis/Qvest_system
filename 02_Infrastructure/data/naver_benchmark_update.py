# -*- coding: utf-8 -*-
"""naver_benchmark_update.py — 벤치마크 **교차검증기**(기본) + 항등 이어붙이기(옵션)

★2026-09-18 축 정규화 — 배율 추정·리베이스 경로 폐기(도훈 "데이터 정확하게 쌓는데 배율이 뭔 상관?").
★2026-09-18 역할 변경 — Naver 는 **정본이 아니다**. 정본은 `03_Universe/Benchmark_price.xlsx`
  (QuantiWise IKS200 → build_index_cache.py). 이 스크립트의 기본 모드는 **검증만**이고
  파일을 쓰지 않는다. 쓰는 것은 `--append` 를 명시했을 때뿐이며, 그때도 정본이 멈춰
  있다는 사실을 **경보로 남긴다** — 조용히 때우는 것이 모든 재발의 온상이었다.

─── 폐기된 것과 그 이유 ──────────────────────────────────────────────────────
  구 구현은 benchmark.parquet 이 **리베이스 체인**(지수 × 8.83)이라서, 생 KPI200 을 붙이기
  전에 "이 파일이 쓰던 배수" 를 median 으로 추정해 되돌려야 했다(SCALE_LOOKBACK_DAYS ·
  SCALE_TOL · 앵커 후퇴 · 재체인). 추정이 한 번 미끄러지면 그날 하루 수익률이 배수비를
  통째로 삼킨다 — 07-27 · 07-29 · 2025-01-02 이 전부 같은 병이다. 축을 지수 포인트로
  정규화하면서 **추정할 것이 사라졌다**: 붙이기는 순수 이어붙이기다.
  seam_guard_config.json 의존도 끊었다(벤치 몫은 benchmark_axis.py 로 이관).

사용:
  python naver_benchmark_update.py                         # 교차검증만 (기본 · 쓰기 없음)
  python naver_benchmark_update.py --append                # 항등 이어붙이기 (정본 정체 시 임시)
  [--start_date YYYY-MM-DD] [--end_date YYYY-MM-DD] [--no-backup] [--quiet]
종료코드: 0=정상 / 1=트립와이어 차단(캐시 미변경) / 2=판정 불가(원천 부재 등)
"""
from __future__ import annotations

import argparse
import ast
import shutil
import sys
from datetime import datetime
from pathlib import Path

import pandas as pd
import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import benchmark_axis as BA          # noqa: E402  (축 규약 단일 정본)

BM_PATH = BA.BM_PATH
NAVER_API = "https://api.finance.naver.com/siseJson.naver"


def fetch_naver_kospi(start_yyyymmdd: str, end_yyyymmdd: str, symbol: str = 'KPI200') -> pd.DataFrame:
    """Naver chart API 에서 일별 종가를 받는다. 반환 DataFrame(Date, Close)."""
    url = (f"{NAVER_API}?symbol={symbol}&requestType=1&startTime={start_yyyymmdd}"
           f"&endTime={end_yyyymmdd}&timeframe=day")
    headers = {'User-Agent': 'Mozilla/5.0 (Linux; rv:109.0) Gecko/20100101'}
    resp = requests.get(url, headers=headers, timeout=15)
    resp.raise_for_status()
    arr = ast.literal_eval(resp.text.strip())
    df = pd.DataFrame(arr[1:], columns=arr[0])
    df = df.rename(columns={'날짜': 'Date', '종가': 'Close'})
    df['Date'] = pd.to_datetime(df['Date'].astype(str), format='%Y%m%d')
    df = df[['Date', 'Close']].sort_values('Date').reset_index(drop=True)
    df['Close'] = df['Close'].astype(float)
    return df


# ── 트립와이어 ────────────────────────────────────────────────────────────────
def tripwire(existing: pd.DataFrame, incoming: pd.DataFrame, mf: dict) -> list:
    """붙이기 **전에** 건다. 하나라도 걸리면 쓰지 않는다 — 캐시는 손대지 않는다.

    ★배율을 추정하지 않으므로 검사는 "같은 축인가" 하나로 단순해진다:
      T1 겹치는 날의 레벨이 일치하는가            (|new/old - 1| <= tol)
      T2 그 일치가 하루 사이 계단을 타지 않는가    (이음매 = 축이 갈린 자리의 지문)
      T3 이어붙인 경계의 하루 수익률이 상한 안인가 (레벨 단절은 큰 수익률로 드러난다)
      T4 받아온 시리즈가 정말 그 지수인가          (일간 수익률 정체 대조)
    """
    fails = []
    tol = mf['tolerance']
    seam_tol = mf['seam_tolerance']
    mx = mf['max_abs_daily_return']

    ov = existing.merge(incoming.rename(columns={'Close': 'nv'})[['Date', 'nv']],
                        on='Date', how='inner')
    ov = ov[(ov['nv'] > 0) & ov['BM_Close'].notna()].sort_values('Date').reset_index(drop=True)
    if len(ov) < 5:
        fails.append(f"T0 겹치는 날짜 {len(ov)}개 (<5) — "
                     f"검증 불가하므로 붙이지 않는다")
        return fails

    ratio = ov['BM_Close'] / ov['nv']
    dev = float((ratio - 1.0).abs().max())
    if dev > tol:
        i = (ratio - 1.0).abs().idxmax()
        fails.append(f"T1 캕 불일치: |신/구-1| 최대 {dev:.3e} > {tol:g} "
                     f"(@{ov['Date'].iloc[i].date()}, 기존 {ov['BM_Close'].iloc[i]:.2f} vs "
                     f"naver {ov['nv'].iloc[i]:.2f})")
    seam = (ratio / ratio.shift(1) - 1.0).abs()
    if seam.notna().any():
        ms = float(seam.max())
        if ms > seam_tol:
            fails.append(f"T2 이음매: 공통일 비율이 하루 사이 "
                         f"{ms:.3e} 변화 > {seam_tol:g} (@{ov['Date'].iloc[seam.idxmax()].date()})")

    tail = incoming[incoming['Date'] > existing['Date'].max()]
    if len(tail):
        anchor = float(existing['BM_Close'].iloc[-1])
        joined = pd.concat([pd.Series([anchor]), tail['Close']], ignore_index=True)
        rets = joined.pct_change().iloc[1:]
        worst = float(rets.abs().max())
        if worst > mx:
            fails.append(f"T3 경계 수익률 max|ret|={worst:.4f} > {mx:g} "
                         f"(레벨 단절 의심)")

    nvr = incoming.copy()
    nvr['nret'] = nvr['Close'].pct_change()
    idc = existing.merge(nvr[['Date', 'nret']], on='Date', how='inner')
    idc = idc[idc['nret'].notna() & idc['BM_Ret'].notna()]
    if len(idc) >= 20:
        agree = float(((idc['nret'] - idc['BM_Ret']).abs() < 1e-6).mean())
        if agree < 0.90:
            fails.append(f"T4 정체 불일치: 일간수익률이 "
                         f"{agree:.1%}만 일치 (기준 90%, n={len(idc)}) — "
                         f"symbol=KPI200 확인")

    # T5 — **붙일 값 자체**를 독립 원천(정본 xlsx · KRX)과 대조한다.
    #   ★왜 따로 필요한가(2026-09-18 자기 검사에서 적발): T1·T2 는 **겹치는 날**만 본다.
    #     단절이 정확히 이어붙임 경계에서 시작하면(= 새로 붙는 날만 다른 축) 겹침이 0 이라
    #     구조적으로 보이지 않는다. 그리고 그것이 바로 재발했던 형태다 — 호출부가
    #     `10 days ago` 라 이음매가 매일 하루씩 전진했다.
    #   ★독립 원천이 그 날을 못 덮으면 **그 날은 검증되지 않은 것**이지 통과한 것이 아니다.
    #     그 경우는 게이트 축 C 가 나중에(원천이 도착하면) 잡는다 — 여기서 초록을 만들지 않는다.
    if len(tail):
        try:
            ref = BA.canonical_reference()
        except Exception:
            ref = None
        if ref is not None and len(ref):
            xr = tail.merge(ref.rename(columns={'ref_close': 'rc'})[['Date', 'rc']],
                            on='Date', how='inner')
            xr = xr[xr['rc'] > 0]
            if len(xr):
                dv = float((xr['Close'] / xr['rc'] - 1.0).abs().max())
                if dv > tol:
                    i = (xr['Close'] / xr['rc'] - 1.0).abs().idxmax()
                    fails.append(f"T5 붙일 값이 독립 원천과 "
                                 f"다름: 최대 {dv:.3e} > {tol:g} "
                                 f"(@{xr['Date'].loc[i].date()}, naver {xr['Close'].loc[i]:.2f} vs "
                                 f"정본 {xr['rc'].loc[i]:.2f})")
    return fails


def run(start_date: str | None, end_date: str | None, do_append: bool,
        backup: bool = True, quiet: bool = False) -> int:
    say = (lambda *a: None) if quiet else print
    mf = BA.read_manifest()
    if end_date is None:
        end_date = datetime.now().strftime('%Y-%m-%d')
    if start_date is None:
        start_date = (pd.to_datetime(end_date) - pd.Timedelta(days=60)).strftime('%Y-%m-%d')

    if not BM_PATH.exists():
        say(f'[naver_benchmark] 대상 부재 — {BM_PATH}')
        return 2

    bm = pd.read_parquet(BM_PATH)
    bm['Date'] = pd.to_datetime(bm['Date'])
    bm = bm.sort_values('Date').reset_index(drop=True)

    s = pd.to_datetime(start_date).strftime('%Y%m%d')
    e = pd.to_datetime(end_date).strftime('%Y%m%d')
    say(f'[naver_benchmark] Naver KPI200 {s} ~ {e} 조회 (모드='
        f'{"append" if do_append else "verify"})...')
    try:
        naver = fetch_naver_kospi(s, e, symbol='KPI200')
    except Exception as ex:
        say(f'  ★조회 실패({ex.__class__.__name__}: {ex}) — '
            f'캐시 미변경')
        BA.write_alert('naver_fetch_failed', f'Naver 조회 실패: {ex}')
        return 2
    say(f'  Naver {len(naver)}행, 최신={naver.Date.max().date()}')

    # 심볼 sanity: 코스피 종합(수천대) 오심볼 회귀 차단 — **생 naver 레벨**에서 검사.
    if float(naver['Close'].max()) > 3000:
        msg = (f"symbol sanity FAIL: naver 최대 {float(naver['Close'].max()):.0f} — "
               f"코스피200 아닌 종합 의심")
        say(f'  ★{msg}')
        BA.write_alert('naver_symbol_sanity', msg)
        return 1

    fails = tripwire(bm, naver, mf)
    if fails:
        say('  ★트립와이어 발화 — 캐시를 손대지 않았습니다:')
        for f in fails:
            say(f'    - {f}')
        BA.write_alert('benchmark_tripwire', '; '.join(fails),
                       {'mode': 'append' if do_append else 'verify',
                        'bm_max': bm['Date'].max().strftime('%Y-%m-%d')})
        return 1
    say('  트립와이어 통과 — Naver 와 캐시가 같은 축 위에 있다')

    if not do_append:
        BA.clear_alert()
        say('  [verify] 기본 모드는 검증만 한다 — '
            '쓰기는 --append 명시 시에만.')
        return 0

    # ── 항등 이어붙이기 (배율 없음 — 생 KPI200 포인트 그대로) ────────────────
    tail = naver[naver['Date'] > bm['Date'].max()].copy()
    if not len(tail):
        say('  새 거래일 없음 — 미변경')
        return 0
    add = pd.DataFrame({'Date': tail['Date'].values,
                        'BM_Close': tail['Close'].astype('float64').values,
                        'BM_Src': 'naver_kpi200'})
    keep = bm.copy()
    if 'BM_Src' not in keep.columns:
        keep['BM_Src'] = 'legacy_unlabeled'
    combined = pd.concat([keep[['Date', 'BM_Close', 'BM_Src']], add], ignore_index=True)
    combined = combined.drop_duplicates('Date', keep='first').sort_values('Date').reset_index(drop=True)
    ret = combined['BM_Close'] / combined['BM_Close'].shift(1) - 1.0
    ret.iloc[0] = float(bm['BM_Ret'].iloc[0]) if pd.notna(bm['BM_Ret'].iloc[0]) else 0.0
    combined['BM_Ret'] = ret.astype('float64')
    combined = combined[['Date', 'BM_Close', 'BM_Ret', 'BM_Src']]

    # 사후 가드: 앵커 이전 완전 불변 + 행 축소 금지
    h0 = bm[bm['Date'] <= bm['Date'].max()].reset_index(drop=True)
    h1 = combined[combined['Date'] <= bm['Date'].max()].reset_index(drop=True)
    if not (len(h0) == len(h1) and h0['BM_Close'].equals(h1['BM_Close'])):
        say('  ★가드 FAIL: 기존 구간이 변경됨 — 중단')
        BA.write_alert('benchmark_append_guard', '기존 구간 변경 감지')
        return 1
    if len(combined) < len(bm):
        say(f'  ★가드 FAIL: 행 축소 ({len(bm)}→{len(combined)}) — 중단')
        return 1

    if backup:
        ts = datetime.now().strftime('%Y%m%d_%H%M%S')
        bak = BM_PATH.with_name(BM_PATH.name + f'.bak_naver_patch_{ts}')
        shutil.copy(BM_PATH, bak)
        say(f'  Backup: {bak.name}')
        gone = BA.prune_backups('benchmark.parquet.bak_naver_patch_*')
        if gone:
            say(f'  오래된 백업 {len(gone)}개 정리 '
                f'(최근 {BA.BACKUP_KEEP}개 보존)')

    BA.write_benchmark_parquet(combined, BM_PATH)
    say(f'  항등 이어붙임 {len(add)}행 — 총 {len(combined)}행, '
        f'최신 {combined.Date.max().date()} @ {combined.BM_Close.iloc[-1]:.2f}')
    # ★정본이 아니다 — 때웠다는 사실을 남긴다. 조용한 때우기가 재발의 온상이었다.
    BA.write_alert('canonical_stale_patched',
                   '정본 xlsx 미갱신 상태에서 Naver 로 '
                   '임시 이어붙였음 — Benchmark_price.xlsx 갱신 필요',
                   {'appended_rows': int(len(add)),
                    'latest': combined.Date.max().strftime('%Y-%m-%d')})
    return 0


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument('--start_date', type=str, default=None)
    p.add_argument('--end_date', type=str, default=None)
    p.add_argument('--append', action='store_true',
                   help='항등 이어붙이기(정본 xlsx 정체 시 임시 때우기 — 경보를 남긴다)')
    p.add_argument('--verify', action='store_true', help='(기본값) 검증만 — 쓰기 없음')
    p.add_argument('--no-backup', action='store_true')
    p.add_argument('--quiet', action='store_true')
    a = p.parse_args()
    if a.append and a.verify:
        print('[naver_benchmark] --append 와 --verify 를 동시에 줄 수 없다')
        return 2
    return run(a.start_date, a.end_date, do_append=a.append,
               backup=not a.no_backup, quiet=a.quiet)


if __name__ == '__main__':
    sys.exit(main())
