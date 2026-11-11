# -*- coding: utf-8 -*-
"""엔진별 메타 병합 — 허용 목록 필드만 읽어 낸다.
읽지 않는 것(값을 출력 · 저장하지 않는다): 등급(grade · essence · grade_v3 …) · PORT_t · 수익 · 위기 방어(cr_verdict · behavior_card …).
읽는 것: FIDELITY 신고(구성 · 논문 원형 · 단계 이름) · lane_provenance(논문 키 · url) · 등록부 인계 기록의 비성과 필드 ·
        레인 산출의 측정 축 블록(실효 시작 상태 · 신호 커버리지 개수) · 보유 표의 날짜별 종목 개수.
"""
import json, os, sys, csv, glob, statistics, datetime

ROOT = sys.argv[1]; SCR = sys.argv[2]
STRAT = os.path.join(ROOT, '04_Research', 'strategies')
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

reg = rj(os.path.join(ROOT, '06_Registry', 'research_programs.json'))
hand = {}
for p in reg.get('programs', []):
    for w in ('queue', 'consumed'):
        for it in p.get(w, []) or []:
            if it.get('kind') != 'engine': continue
            ep = (it.get('engine_path') or '').replace('\\', '/')
            d = os.path.basename(os.path.dirname(ep)) if ep else None
            if not d: continue
            rec = {k: it.get(k) for k in REG_OK if k in it}
            rec['program'] = p.get('id'); rec['where'] = w
            hand.setdefault(d, []).append(rec)
for it in reg.get('paper_routing', {}).get('unrouted', []) or []:
    if it.get('kind') != 'engine': continue
    ep = (it.get('engine_path') or '').replace('\\', '/')
    d = os.path.basename(os.path.dirname(ep)) if ep else None
    if not d: continue
    rec = {k: it.get(k) for k in REG_OK if k in it}
    rec['program'] = None; rec['where'] = 'unrouted'
    hand.setdefault(d, []).append(rec)

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

out = []
for d in sorted(glob.glob(os.path.join(STRAT, 'RP_AUTO_*'))):
    nm = os.path.basename(d)
    if not os.path.exists(os.path.join(d, 'engine.R')): continue
    fj = rj(os.path.join(d, 'FIDELITY.json')) or {}
    lp = rj(os.path.join(d, 'lane_provenance.json')) or {}
    fa = rj(os.path.join(d, 'fidelity_audit.json')) or {}
    hs = sorted(hand.get(nm, []), key=lambda r: (r.get('enqueued_at') or r.get('held_at') or ''), reverse=True)
    h = hs[0] if hs else {}
    art = norm_art(h.get('artifacts'))
    ar = rj(os.path.join(art, 'authoritative_remeasure.json')) if art else None
    ax = {}
    if ar:
        ma = ar.get('measurement_axis') or {}
        es = ma.get('effective_start') or {}
        sc = ma.get('signal_coverage') or {}
        rp = ar.get('replication') or {}
        ax = {'epoch': ma.get('epoch'),
              'es': {k: es.get(k) for k in ('status', 'basis', 'first_signal_date', 'n_signal_dates', 'date', 'n_dates_cut', 'breadth_at_start',
                                           'holdings_at_start', 'breadth_max', 'holdings_median', 'n_dates_below_after') if k in es},
              'cov': {k: sc.get(k) for k in ('status', 'basis', 'first_signal_date', 'last_signal_date', 'n_signal_dates') if k in sc},
              'rep': {k: rp.get(k) for k in ('fidelity', 'rebalance', 'n_max', 'has_short') if k in rp}}
    ps = fj.get('portfolio_spec') if isinstance(fj.get('portfolio_spec'), dict) else {}
    steps = [{'step': s.get('step'), 'status': s.get('status')} for s in (fj.get('paper_steps') or []) if isinstance(s, dict)]
    sp = fj.get('source_paper') or fj.get('paper') or {}
    out.append({'dir': nm, 'paper_key': lp.get('paper_key') or h.get('paper_key') or (sp.get('paper_key') if isinstance(sp, dict) else None),
                'paper_url': lp.get('paper_url'), 'title': h.get('title') or (sp.get('title') if isinstance(sp, dict) else None),
                'lane_mode': lp.get('mode'), 'fidelity': fj.get('fidelity'), 'portfolio_spec': ps,
                'declared_role': fj.get('declared_role'), 'paper_original_form': fj.get('paper_original_form'), 'kept': fj.get('kept'),
                'steps': steps, 'const_names': [c.get('name') for c in (fj.get('constants') or []) if isinstance(c, dict)],
                'audit_verdict_file': fa.get('verdict'),
                'handoff': {k: h.get(k) for k in ('program', 'where', 'routed_by', 'fidelity', 'audit_verdict', 'implementation_suspect', 'has_short',
                                                 'base_id', 'enqueued_at', 'held_at') if k in h},
                'n_handoffs': len(hs), 'artifacts': (h.get('artifacts') or '').replace('\\', '/'), 'axis': ax,
                'holdings': hold_counts(art)})
with open(os.path.join(SCR, 'engine_meta.json'), 'w', encoding='utf-8') as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
print('engines', len(out))
