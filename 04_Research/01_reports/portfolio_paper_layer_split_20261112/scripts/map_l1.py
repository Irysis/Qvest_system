# -*- coding: utf-8 -*-
"""L1 원장(충실구현 소비 기록) → 엔진 디렉터리별 산출 폴더 대응. 허용 목록 키만(base_id · paper_key · base_artifacts · engine_path · opened_at · measurement_axis).
등급 · 성과 키(base_grade · base_essence_history …)는 읽어 내지 않는다. 보유 표에서는 날짜별 종목 개수만 센다."""
import json, os, sys, importlib.util
ROOT = sys.argv[1]; SCR = sys.argv[2]
spec = importlib.util.spec_from_file_location('mm', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'merge_meta_lib.py'))
mm = importlib.util.module_from_spec(spec); spec.loader.exec_module(mm)
d = mm.rj(os.path.join(ROOT, '06_Registry', 'reinforce_ledger_l1.json'))
OK = ('base_id', 'paper_key', 'paper_id', 'base_artifacts', 'engine_path', 'opened_at', 'measurement_axis', 'status')
by = {}
for e in d.get('entries', []):
    ep = str(e.get('engine_path') or '').replace('\\', '/')
    if '/RP_AUTO_' not in ep: continue
    nm = os.path.basename(os.path.dirname(ep))
    by.setdefault(nm, []).append({k: e.get(k) for k in OK if k in e})
out = {}
for nm, es in by.items():
    es = sorted(es, key=lambda r: str(r.get('opened_at') or ''))
    e = es[-1]
    art = mm.norm_art(str(e.get('base_artifacts') or '')) if e.get('base_artifacts') else None
    if art and not os.path.isabs(art): art = os.path.join(ROOT, art)
    s = mm.rj(os.path.join(art, '01_strategy_spec.json')) if art else None
    ar = (mm.rj(os.path.join(art, 'authoritative_remeasure.json')) or {}) if art else {}
    ma = ar.get('measurement_axis') or {}; esx = ma.get('effective_start') or {}
    out[nm] = {'n_entries': len(es), 'paper_key': e.get('paper_key'), 'base_id': e.get('base_id'), 'artifacts': str(e.get('base_artifacts') or '').replace('\\', '/'),
               'axis_label': e.get('measurement_axis') if isinstance(e.get('measurement_axis'), str) else None,
               'spec': ({k: s.get(k) for k in ('construction', 'weight_method', 'rebalance', 'universe', 'n_max', 'has_short', 'source_paper_url', 'strategy_idea')} if isinstance(s, dict) else None),
               'epoch': ma.get('epoch'), 'es': {k: esx.get(k) for k in ('status', 'basis', 'n_signal_dates', 'first_signal_date') if k in esx},
               'holdings': mm.hold_counts(art) if art else None}
with open(os.path.join(SCR, 'engine_l1.json'), 'w', encoding='utf-8') as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
print('L1 mapped', len(out))
