# -*- coding: utf-8 -*-
"""엔진별 메타 병합 — 허용 목록 필드만 읽어 낸다.
읽지 않는 것(값을 출력 · 저장하지 않는다): 등급(grade · essence · grade_v3 …) · PORT_t · 수익 · 위기 방어(cr_verdict · behavior_card …).
읽는 것: FIDELITY 신고(구성 · 논문 원형 · 단계 이름) · lane_provenance(논문 키 · url) · 등록부 인계 기록의 비성과 필드 ·
        레인 산출의 측정 축 블록(실효 시작 상태 · 신호 커버리지 개수) · 보유 표의 날짜별 종목 개수.
"""
import json, os, sys, csv, glob, statistics, datetime
ROOT = sys.argv[1]


REG_OK = ('key', 'kind', 'title', 'paper_key', 'base_id', 'fidelity', 'artifacts', 'engine_path', 'routed_by',
          'implementation_suspect', 'has_short', 'audit_verdict', 'enqueued_at', 'held_at', 'holdings_claim_mismatch', 'engine_md5')

def rj(p):
    try:
        with open(p, encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return None

def norm_art(a):
    if not a: return None
    a = a.replace('\\', '/')
    i = a.find('stage_artifacts/')
    return os.path.join(ROOT, a[i:]) if i >= 0 else a


def hold_counts(art):
    """04_holdings.csv — 날짜별 종목 개수만(비중 부호로 롱/숏 구분 · 값 자체는 보관하지 않는다)."""
    f = os.path.join(art, '04_holdings.csv') if art else None
    if not f or not os.path.exists(f): return None
    TOL = 1e-9
    per = {}
    with open(f, encoding='utf-8', newline='') as fh:
        rd = csv.reader(fh); hdr = next(rd)
        try:
            di = hdr.index('date'); wi = hdr.index('target_weight')
        except ValueError:
            return {'err': 'columns'}
        for row in rd:
            if len(row) <= max(di, wi): continue
            try: w = float(row[wi])
            except ValueError: continue
            c = per.setdefault(row[di], [0, 0, 0])
            if w > TOL: c[0] += 1
            elif w < -TOL: c[1] += 1
            else: c[2] += 1
    if not per: return {'err': 'empty'}
    ds = sorted(per)
    pos = [per[d][0] for d in ds]; neg = [per[d][1] for d in ds]; tot = [per[d][0] + per[d][1] for d in ds]
    dd = [datetime.date.fromisoformat(d[:10]) for d in ds]
    gaps = [(dd[i + 1] - dd[i]).days for i in range(len(dd) - 1)]
    q = lambda v: [min(v), statistics.median(v), max(v)] if v else None
    return {'n_dates': len(ds), 'first': ds[0], 'last': ds[-1], 'long': q(pos), 'short': q(neg), 'names': q(tot),
            'n_dates_with_short': sum(1 for x in neg if x > 0), 'n_dates_no_long': sum(1 for x in pos if x == 0),
            'gap_cal_days': q(gaps), 'n_dates_names_ge50': sum(1 for x in tot if x >= 50), 'n_dates_names_le25': sum(1 for x in tot if x <= 25),
            'n_dust': sum(per[d][2] for d in ds)}

