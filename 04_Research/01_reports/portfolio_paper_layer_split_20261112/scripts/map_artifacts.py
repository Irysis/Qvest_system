# -*- coding: utf-8 -*-
"""레인 산출 폴더 → 엔진 디렉터리 대응(01_strategy_spec.json 의 factor_engine_path) + 최신 산출의 보유 개수 · 측정 축 블록.
허용 목록 필드만 읽는다(성과 필드 미열람). 보유 표에서는 날짜별 종목 개수만 센다."""
import json, os, sys, glob
sys.path.insert(0, sys.argv[2])
ROOT = sys.argv[1]; SCR = sys.argv[2]
import importlib.util
spec = importlib.util.spec_from_file_location('mm', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'merge_meta_lib.py'))
mm = importlib.util.module_from_spec(spec); spec.loader.exec_module(mm)

runs = {}
for d in sorted(glob.glob(os.path.join(ROOT, 'stage_artifacts', 'replication', '2026*'))):
    s = mm.rj(os.path.join(d, '01_strategy_spec.json'))
    if not isinstance(s, dict): continue
    ep = str(s.get('factor_engine_path') or '').replace('\\', '/')
    if '/04_Research/strategies/RP_AUTO_' not in ep or not ep.endswith('/engine.R'): continue
    nm = os.path.basename(os.path.dirname(ep))
    runs.setdefault(nm, []).append({'run': os.path.basename(d), 'construction': s.get('construction'), 'weight_method': s.get('weight_method'),
                                    'rebalance': s.get('rebalance'), 'universe': s.get('universe'), 'n_max': s.get('n_max'), 'has_short': s.get('has_short'),
                                    'has_auth': os.path.exists(os.path.join(d, 'authoritative_remeasure.json')),
                                    'has_hold': os.path.exists(os.path.join(d, '04_holdings.csv'))})
out = {}
for nm, rs in runs.items():
    rs = sorted(rs, key=lambda r: r['run'])
    full = [r for r in rs if r['has_hold']]
    last = (full or rs)[-1]
    art = os.path.join(ROOT, 'stage_artifacts', 'replication', last['run'])
    ar = mm.rj(os.path.join(art, 'authoritative_remeasure.json')) or {}
    ma = ar.get('measurement_axis') or {}; es = ma.get('effective_start') or {}; sc = ma.get('signal_coverage') or {}
    out[nm] = {'n_runs': len(rs), 'last': last, 'epoch': ma.get('epoch'),
               'es': {k: es.get(k) for k in ('status', 'basis', 'first_signal_date', 'n_signal_dates', 'date', 'n_dates_cut', 'breadth_at_start',
                                            'holdings_at_start', 'breadth_max', 'holdings_median', 'n_dates_below_after') if k in es},
               'cov': {k: sc.get(k) for k in ('status', 'basis', 'first_signal_date', 'last_signal_date', 'n_signal_dates') if k in sc},
               'holdings': mm.hold_counts(art)}
with open(os.path.join(SCR, 'engine_runs.json'), 'w', encoding='utf-8') as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
print('mapped engines', len(out))
