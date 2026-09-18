# -*- coding: utf-8 -*-
"""rebuild_benchmark_canonical.py — `.cache/benchmark.parquet` 정본 재구축 (2026-09-18 신설)

하는 일: BM_Close 를 **공표 코스피200 지수 레벨(포인트) 그대로** 로 되돌린다.
        BM_Ret 은 그 정본 종가에서 재계산한다. 배율 개념은 없다.

─── 왜 (도훈 2026-09-18 "근본적으로 좀 수정하자. 도대체 몇 번째 버그냐") ────────
  구 `.cache/benchmark.parquet` 는 지수의 8.83배 위에 있는 **리베이스 체인**이었다.
  체인이면 새 값을 붙일 때마다 "이 파일이 쓰던 배수" 를 추정해야 하고, 추정이 한 번
  미끄러지면 그날 하루 수익률이 배수비를 통째로 삼킨다. 실측 재발:
      2026-07-27 (08-08 일회성 수리) · 2026-07-29 (08-09 또 수리) · 2025-01-02 (미발견)
  날짜를 박은 수리는 원리적으로 못 버틴다 — 호출부가 `10 days ago` 라 이음매가 매일
  하루씩 전진하기 때문이다. ⇒ 축을 바꾼다. 추정할 것이 없으면 미끄러질 것도 없다.

─── 원천 우선순위 (도훈 지시 — 인터넷이 아니라 인프라 안에서) ───────────────────
  1. `03_Universe/Benchmark_price.xlsx` (QuantiWise IKS200)  ← 정본. 생 포인트.
  2. `.cache/krx/kospi_index/*.parquet`                      ← xlsx 가 못 덮는 최근 구간
  3. 구 체인 ÷ **실측** 구간배수                              ← 위 둘 다 없는 날의 구제
     (배수는 하드코딩하지 않는다 — 참조와의 비율에서 구간을 자동 검출해 쓰고 로그에 남긴다)
  ※Naver 는 정본에서 빠졌다 — 교차검증 전용(naver_benchmark_update.py --verify).

─── 날짜 격자는 **바꾸지 않는다** (중요) ──────────────────────────────────────
  이 재구축은 **레벨 축만** 고친다. 행을 더하거나 빼지 않는다.
  benchmark.parquet 은 trading_calendar.R 의 거래일 유일 권위이므로, 행 집합을 건드리면
  축 이전이 아니라 캘린더 변경이 된다 — 그건 별개 과제이고 처분 대기 중이다:
    · 1990~98 토요장 438행 = **진짜 세션인데 benchmark 에만 없다**(indices/xlsx 엔 있다)
    · 2024-12-30 = 반대로 **유령**(QuantiWise RAWDATA 2,504종목·trading_calendar·현 benchmark
      셋 다 2024 마지막 거래일 = 12-27. xlsx 지수 시트에만 행이 있다)
  ⇒ 행마다 갈리므로 통째로 복원/삭제할 수 없다. 여기서는 손대지 않고 보고만 한다.
  ★부수효과(정직하게 적는다): 격자에 없는 세션의 수익률은 구판에서 **버려졌고**,
    재구축 뒤에는 다음 거래일 수익률에 **합쳐진다**(레벨 시리즈의 올바른 거동).
    2025-01-02 의 유령 +0.379% 가 사라지는 것이 정확히 이 기전이다.

사용:
  python 02_Infrastructure/data/rebuild_benchmark_canonical.py             # dry-run
  python 02_Infrastructure/data/rebuild_benchmark_canonical.py --write     # 실쓰기(백업)
  [--path P] [--ignore-kill-switch] [--json-out F]
종료코드: 0=정상(또는 dry-run 정상) / 1=가드 실패·차단 / 2=판정 불가
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
import benchmark_axis as BA          # noqa: E402  (축 규약 단일 정본)

# 구간 검출: 이 상대오차 안에서 같은 비율이면 같은 구간이다.
SEGMENT_EPS = 1e-9
# 보고할 만한 구간의 최소 길이(세션). 이보다 짧은 런은 잡음으로 보고 앞 구간에 붙인다.
SEGMENT_MIN_ROWS = 5


# ── 구간(배수) 자동 검출 ──────────────────────────────────────────────────────
def detect_legacy_segments(old_bm: pd.DataFrame, ref: pd.DataFrame) -> list:
    """구 체인과 참조 지수의 비율에서 **구간**을 자동 검출한다(배수 하드코딩 금지).

    반환: [{'start','end','scale','n'}] — 날짜 오름차순.
    ★이 값들은 '설정' 이 아니라 **실측**이다. 새 축에서는 전부 1.0 이 되어야 하고,
      1.0 이 아닌 구간이 남아 있다는 사실 자체가 구 체인의 지문이다.
    """
    m = old_bm[['Date', 'BM_Close']].merge(ref[['Date', 'ref_close']], on='Date', how='inner')
    m = m[(m['ref_close'] > 0) & m['BM_Close'].notna()].sort_values('Date').reset_index(drop=True)
    if not len(m):
        return []
    m['ratio'] = m['BM_Close'] / m['ref_close']
    segs = []
    cur = {'start': m['Date'].iloc[0], 'end': m['Date'].iloc[0],
           'scale': float(m['ratio'].iloc[0]), 'n': 1}
    for i in range(1, len(m)):
        rr = float(m['ratio'].iloc[i])
        if abs(rr / cur['scale'] - 1.0) <= SEGMENT_EPS:
            cur['end'] = m['Date'].iloc[i]
            cur['n'] += 1
        else:
            segs.append(cur)
            cur = {'start': m['Date'].iloc[i], 'end': m['Date'].iloc[i], 'scale': rr, 'n': 1}
    segs.append(cur)
    return segs


def scale_for_date(segs: list, d: pd.Timestamp) -> float:
    """날짜 d 를 덮는 구간의 배수. 없으면 **직전** 구간, 그것도 없으면 첫 구간."""
    if not segs:
        return 1.0
    for s in segs:
        if s['start'] <= d <= s['end']:
            return s['scale']
    prev = [s for s in segs if s['end'] < d]
    if prev:
        return prev[-1]['scale']
    return segs[0]['scale']


# ── 재구축 ────────────────────────────────────────────────────────────────────
def build_canonical(old_bm: pd.DataFrame, ref: pd.DataFrame, segs: list,
                    decimals: int) -> pd.DataFrame:
    """구 격자 위에서 정본 종가를 조립한다. 행은 더하지도 빼지도 않는다."""
    ref_map = ref.set_index('Date')
    grid = old_bm[['Date', 'BM_Close']].sort_values('Date').reset_index(drop=True)

    closes, srcs = [], []
    for _, row in grid.iterrows():
        d = row['Date']
        if d in ref_map.index:
            closes.append(float(ref_map.at[d, 'ref_close']))
            srcs.append(str(ref_map.at[d, 'ref_source']))
        else:
            sc = scale_for_date(segs, d)
            v = float(row['BM_Close']) / sc if (sc and np.isfinite(sc) and sc > 0) else float(row['BM_Close'])
            # 공표 자릿수로 되돌리면 공표값과 **정확히** 일치한다(실측 검증됨).
            closes.append(round(v, decimals))
            srcs.append('legacy_chain_rescaled')

    out = pd.DataFrame({'Date': grid['Date'], 'BM_Close': closes, 'BM_Src': srcs})
    ret = out['BM_Close'] / out['BM_Close'].shift(1) - 1.0
    # ★첫 행 규약은 구판을 승계한다(0.0). NA↔0 전환은 그 자체로 소비자 가시 변경이다.
    ret.iloc[0] = 0.0
    out['BM_Ret'] = ret.astype('float64')
    return out[['Date', 'BM_Close', 'BM_Ret', 'BM_Src']]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--path', default=str(BA.BM_PATH))
    ap.add_argument('--write', action='store_true', help='실제로 파일을 교체한다(기본 dry-run)')
    ap.add_argument('--ignore-kill-switch', action='store_true')
    ap.add_argument('--json-out', default=None, help='보고서를 JSON 으로도 남긴다')
    args = ap.parse_args()

    bm_path = Path(args.path)
    print('=== benchmark 정본 재구축 (축 = 공표 코스피200 포인트) ===')
    print(f'  대상 : {bm_path}')
    if not bm_path.exists():
        print('  ★대상 부재 — 판정 불가')
        return 2

    old = pd.read_parquet(bm_path)
    old['Date'] = pd.to_datetime(old['Date'])
    old = old.sort_values('Date').reset_index(drop=True)
    n0 = len(old)
    print(f'  구판 : {n0}행  {old.Date.min().date()} ~ {old.Date.max().date()}')

    ref = BA.canonical_reference()
    if not len(ref):
        print('  ★정본 참조 부재(xlsx · KRX 둘 다) — 판정 불가')
        return 2
    nqw = int((ref['ref_source'] == 'quantiwise_iks200').sum())
    nkx = int((ref['ref_source'] == 'krx_kospi200').sum())
    print(f'  참조 : {len(ref)}행 (xlsx {nqw} + KRX {nkx})  '
          f'{ref.Date.min().date()} ~ {ref.Date.max().date()}')

    # ── 구간 검출 (배수는 실측으로 구한다 — 하드코딩 없음) ────────────────────
    segs = detect_legacy_segments(old, ref)
    big = [s for s in segs if s['n'] >= SEGMENT_MIN_ROWS]
    print(f'\n  [구 체인 구간 검출] 총 {len(segs)}구간 (n>={SEGMENT_MIN_ROWS} 인 것 {len(big)}개)')
    for s in big[-6:]:
        print(f'    {s["start"].date()} ~ {s["end"].date()}  배수={s["scale"]:.9f}  n={s["n"]}')
    if len(big) > 6:
        print(f'    (앞 {len(big) - 6}개 생략 — 1999년 이전은 주 단위 계단이다: '
              f'결손 세션 때문이지 배수 규약이 아니다)')
    seams = []
    for a, b in zip(big, big[1:]):
        seams.append({'date': b['start'].strftime('%Y-%m-%d'),
                      'prev_scale': a['scale'], 'new_scale': b['scale'],
                      'jump': b['scale'] / a['scale'] - 1.0})

    # ── 조립 ──────────────────────────────────────────────────────────────────
    mf = BA.read_manifest()
    new = build_canonical(old, ref, segs, mf['decimals'])

    # ── 전후 보고 ─────────────────────────────────────────────────────────────
    cmp_ = old[['Date', 'BM_Close', 'BM_Ret']].merge(
        new[['Date', 'BM_Close', 'BM_Ret', 'BM_Src']], on='Date', suffixes=('_old', '_new'))
    dret = (cmp_['BM_Ret_new'] - cmp_['BM_Ret_old']).abs()
    changed = cmp_[dret > 1e-12].copy()
    changed['d'] = dret[dret > 1e-12]
    src_counts = new['BM_Src'].value_counts().to_dict()

    print(f'\n--- 전후 ---')
    print(f'  행       : {n0} → {len(new)}  (격자 불변)')
    print(f'  기간     : {new.Date.min().date()} ~ {new.Date.max().date()}')
    print(f'  레벨     : {old.BM_Close.iloc[-1]:,.4f} → {new.BM_Close.iloc[-1]:,.4f} '
          f'(최종일 {new.Date.iloc[-1].date()})')
    print(f'  provenance: ' + ' · '.join(f'{k}={v}' for k, v in src_counts.items()))
    print(f'  수익률이 바뀐 날: {len(changed)}건 / {len(cmp_)} '
          f'(최대 |Δret| = {float(dret.max()):.6e})')
    if len(changed):
        post99 = changed[changed['Date'] >= '1999-01-01']
        pre99 = changed[changed['Date'] < '1999-01-01']
        print(f'    1999년 이전 {len(pre99)}건 (결손 토요장 438건의 수익률이 월요일에 합쳐진다)')
        print(f'    1999년 이후 {len(post99)}건 — 전부 나열:')
        for _, r in post99.sort_values('Date').iterrows():
            print(f'      {r["Date"].date()}  BM_Ret {r["BM_Ret_old"]:+.6f} → {r["BM_Ret_new"]:+.6f} '
                  f'(Δ{r["BM_Ret_new"] - r["BM_Ret_old"]:+.6f})  src={r["BM_Src"]}')

    # ── 사후검증 (가드) ───────────────────────────────────────────────────────
    chk = BA.axis_check(new, ref, tol=mf['tolerance'], seam_tol=mf['seam_tolerance'])
    g = {}
    g['rows_unchanged'] = len(new) == n0
    g['dates_unchanged'] = bool((new['Date'].values == old['Date'].values).all())
    g['close_finite_positive'] = bool(np.isfinite(new['BM_Close']).all() and (new['BM_Close'] > 0).all())
    g['ret_internally_consistent'] = bool(
        float((new['BM_Close'].pct_change().iloc[1:] - new['BM_Ret'].iloc[1:]).abs().max()) < 1e-12)
    g['axis_identity_ok'] = chk['status'] == 'ok'
    g['no_src_unknown'] = bool(new['BM_Src'].notna().all())
    print(f'\n  축 판정: {chk["status"]} — {chk["detail"]}')
    print('\n--- 가드 ---')
    for k, v in g.items():
        print(f'  {k:28s} {"PASS" if v else "★FAIL"}')
    if not all(g.values()):
        print('\n★가드 FAIL — 쓰지 않고 중단합니다.')
        BA.write_alert('rebuild_guard_fail', '정본 재구축 가드 실패 — 캐시 미변경',
                       {k: bool(v) for k, v in g.items()})
        return 1

    report = {
        'schema': 'benchmark_rebuild_report_v1',
        'at': datetime.now().isoformat(timespec='seconds'),
        'rows_before': int(n0), 'rows_after': int(len(new)),
        'date_min': new.Date.min().strftime('%Y-%m-%d'),
        'date_max': new.Date.max().strftime('%Y-%m-%d'),
        'source_counts': {str(k): int(v) for k, v in src_counts.items()},
        'changed_return_dates': int(len(changed)),
        'changed_return_dates_post_1999': [
            {'date': r['Date'].strftime('%Y-%m-%d'), 'old': float(r['BM_Ret_old']),
             'new': float(r['BM_Ret_new'])}
            for _, r in changed[changed['Date'] >= '1999-01-01'].sort_values('Date').iterrows()],
        'max_abs_dret': float(dret.max()) if len(dret) else 0.0,
        'legacy_segments': [
            {'start': s['start'].strftime('%Y-%m-%d'), 'end': s['end'].strftime('%Y-%m-%d'),
             'scale': float(s['scale']), 'n': int(s['n'])} for s in big],
        'legacy_seams': seams,
        'axis_check': {k: (v if not isinstance(v, float) or np.isfinite(v) else None)
                       for k, v in chk.items()},
        'written': False,
    }

    if not args.write:
        print('\n[dry-run] --write 가 없어 파일을 바꾸지 않았습니다.')
        if args.json_out:
            Path(args.json_out).write_text(json.dumps(report, ensure_ascii=False, indent=2),
                                           encoding='utf-8')
        return 0

    # ── 실쓰기 규약 ───────────────────────────────────────────────────────────
    # ★무인 강화 레인이 도는 중에 벤치를 갈아끼우면 진행 중 측정과 완료 측정이 서로
    #   다른 파일 위에 서게 된다 — 킬스위치를 내린 뒤 부를 것.
    if not args.ignore_kill_switch:
        rac = BA.PROJECT_ROOT / '06_Registry' / 'reinforce_auto_config.json'
        try:
            enabled = bool(json.loads(rac.read_text(encoding='utf-8')).get('enabled'))
        except Exception as e:
            print(f'\n★reinforce_auto_config.json 판독 불가({e.__class__.__name__}) — 쓰지 않습니다.')
            return 1
        if enabled:
            print('\n★무인 강화 레인이 켜져 있습니다(enabled=true) — 쓰지 않습니다.')
            return 1

    ts = datetime.now().strftime('%Y%m%d_%H%M%S')
    bak = bm_path.with_name(bm_path.name + f'.bak_axis_migration_{ts}')
    shutil.copy(bm_path, bak)
    print(f'\n백업 → {bak.name}')

    BA.write_benchmark_parquet(new, bm_path)
    print(f'정본 기록 완료 — {len(new)}행')

    manifest = {
        'schema': 'benchmark_axis_v1',
        '_purpose': ('`.cache/benchmark.parquet::BM_Close` 의 저장 규약 선언. '
                     '배율(scale) 필드는 없다 — 규약이 곧 "공표 지수 그대로" 이기 때문이다. '
                     '배율을 선언 가능하게 두면 그 값이 다시 승계되고, 그것이 '
                     '2026-07~09 재발의 기전이었다(도훈 2026-09-18).'),
        'unit': BA.AXIS_UNIT,
        'reference': BA.AXIS_REFERENCE,
        'tolerance': mf['tolerance'],
        'seam_tolerance': mf['seam_tolerance'],
        'decimals': mf['decimals'],
        'source_priority': BA.SOURCE_PRIORITY,
        '_source_priority_note': (
            '1) 03_Universe/Benchmark_price.xlsx (QuantiWise IKS200, build_index_cache.py 경로) '
            '2) .cache/krx/kospi_index/*.parquet (xlsx 미도달 최근 구간) '
            '3) legacy_chain_rescaled = 구 체인 ÷ 실측 구간배수(구제용, 신규 유입 없음). '
            'Naver chart API 는 정본이 아니라 교차검증 전용.'),
        'built_at': datetime.now().isoformat(timespec='seconds'),
        'built_by': 'rebuild_benchmark_canonical.py',
        'rows': int(len(new)),
        'date_min': report['date_min'], 'date_max': report['date_max'],
        'source_counts': report['source_counts'],
        'legacy_seams_detected': seams,
        '_legacy_seams_note': (
            '구 리베이스 체인이 남긴 배수 계단. 사후 감사용 기록이며 어떤 코드도 이 값을 '
            '소비하지 않는다 — 새 축에서 모든 배수는 1.0 이다.'),
        'grid_note': (
            '날짜 격자는 재구축이 바꾸지 않는다(trading_calendar.R 의 거래일 권위). '
            '처분 대기: 1990~98 토요장 438행(진짜 세션인데 benchmark 에만 없음) · '
            '2024-12-30(반대로 유령 — xlsx 지수 시트에만 있음).'),
    }
    BA.write_manifest(manifest)
    print(f'manifest → {BA.MANIFEST_PATH}')

    gone = BA.prune_backups('benchmark.parquet.bak_axis_migration_*')
    if gone:
        print(f'  오래된 축-이전 백업 {len(gone)}개 정리 (최근 {BA.BACKUP_KEEP}개 보존)')
    BA.clear_alert()

    report['written'] = True
    report['backup'] = bak.name
    if args.json_out:
        Path(args.json_out).write_text(json.dumps(report, ensure_ascii=False, indent=2),
                                       encoding='utf-8')
    print(f'\n롤백: copy "{bak}" "{bm_path}"  (manifest 는 .cache/benchmark_axis.json 삭제)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
