# -*- coding: utf-8 -*-
"""논문 id 정규화 **정본** (2026-08-22 신설).

왜 있나:
  같은 대상을 세는데 답이 셋이었다 — 좌초 논문 수가 **154 / 62 / 61**, 재발견이 **27회 / 10회**.
  세 수치 전부 개수는 정확했고 **정규화 규약이 달랐다**:
    · 제목 기준 vs id 기준
    · `arxiv:` 접두 · `v2` 버전접미 제거 여부
    · 창을 자르는가(처리일 이후만) 아닌가
  ⇒ 규약이 없으면 **어느 수치도 인용할 수 없다**. 여기서 한 번 정하고 소비자는 이걸 부른다.

★규약 (이 파일이 정본):
  1. **id 기준**으로 센다. 제목은 표기 변형·부제 절단이 잦아 같은 논문을 둘로 센다.
  2. `arxiv:` / `arXiv:` / `arxiv.org/abs/` 접두를 벗긴다.
  3. `v1`/`v2`… **버전 접미를 벗긴다** — 같은 논문의 개정판은 같은 논문이다.
  4. 공백·대소문자를 정규화한다. curated PDF id 는 파일명 그대로(확장자만 제거).
  5. **창(window)은 호출자가 명시**한다. 이 모듈은 id 만 정규화하고 기간은 정하지 않는다
     — 기간을 여기 숨기면 같은 함수가 호출처마다 다른 답을 낸다.

★이 규약은 `alpha_search_queue_prompt.md` §6 의 'bare arXiv id' 지시와 동일하다
  (그쪽이 먼저 명문화했고, 여기서 코드로 고정한다).
"""
import io
import json
import os
import re
import sys

_PREFIX = re.compile(r'^(?:arxiv\s*:|arxiv\.org/abs/|https?://arxiv\.org/abs/)', re.I)
_VERSUF = re.compile(r'v\d+$', re.I)


def norm_id(x):
    """논문 id 를 정본 형태로. 판별 불가면 빈 문자열(있는 척하지 않는다)."""
    if x is None:
        return ''
    s = str(x).strip()
    if not s:
        return ''
    s = _PREFIX.sub('', s).strip()
    # curated PDF: 확장자만 제거하고 나머지는 보존
    if s.lower().endswith('.pdf'):
        return s[:-4].strip()
    # arXiv 형식(2607.19497)일 때만 버전 접미를 벗긴다 —
    # 임의 문자열에서 끝의 v+숫자를 벗기면 다른 id 를 훼손한다.
    if re.match(r'^\d{4}\.\d{4,5}(v\d+)?$', s, re.I):
        s = _VERSUF.sub('', s)
    return s


def collect_ids(obj, keys=('arxiv_id', 'paper_id', 'id')):
    """중첩 JSON 에서 논문 id 를 재귀 수집해 정규화한 집합으로."""
    out = set()

    def walk(o):
        if isinstance(o, dict):
            for k in keys:
                v = o.get(k)
                if isinstance(v, str):
                    n = norm_id(v)
                    if n:
                        out.add(n)
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)

    walk(obj)
    return out


# ── paper_key 3단 중복 방지 정본 (2026-08-29 v10 신설, 도훈 지시 "중복 수집 방지 규칙") ──
#   왜 있나: 기존 수집 dedup 은 source_url 완전일치 + 제목 소문자 완전일치뿐이었다.
#   arXiv 버전 접미(v2)가 다르면 같은 논문이 두 번 수집됐고, 같은 논문이 arXiv 와 SSRN
#   양쪽에서 오면 URL 이 달라 잡히지 않았다. recency 제약을 제거하고 relevance 정렬로
#   바꾸면(v10) 같은 고전이 매일 재수집되므로, 키 규약 없이는 수집기가 성립하지 않는다.
#   ★우선순위 고정 3단 (판별 가능한 가장 강한 축 하나만 쓴다):
#     1. axv:<arxiv id>  — norm_id 정본(접두·버전 접미 제거)
#     2. doi:<doi>       — 접두(doi:/dx.doi.org/doi.org) 제거 + 소문자
#     3. ttl:<sha1 12자> — NFKC → 소문자 → 영숫자·한글만 → 공백 collapse 한 제목의 해시
#   판별 불가면 '' — 있는 척하지 않는다(norm_id 규약과 동일 정신).

_ARXIV_URL = re.compile(
    r'arxiv\.org/(?:abs|pdf)/([^\s?#]+?)(?:\.pdf)?(?:[?#].*)?$', re.I)
_DOI_PREFIX = re.compile(r'^(?:doi\s*:|https?://(?:dx\.)?doi\.org/)', re.I)


def arxiv_id_from(x):
    """URL(abs/pdf)·접두 표기 어디서든 arXiv id 를 추출·정규화. 없으면 ''."""
    if x is None:
        return ''
    s = str(x).strip()
    if not s:
        return ''
    m = _ARXIV_URL.search(s)
    if m:
        cand = norm_id(m.group(1))
        return cand
    n = norm_id(s)
    return n if re.match(r'^\d{4}\.\d{4,5}$', n) else ''


def norm_doi(x):
    """DOI 를 정본 형태(소문자, 접두 제거)로. DOI 가 아니면 ''."""
    if x is None:
        return ''
    s = str(x).strip()
    if not s:
        return ''
    s = _DOI_PREFIX.sub('', s).strip().lower().rstrip('/')
    return s if s.startswith('10.') else ''


def norm_title(x):
    """제목 정규화: NFKC → 소문자 → 영숫자·한글 외 → 공백 → collapse.

    제목은 표기 변형(콜론·대시·부제 유무)이 잦아 완전일치 대조가 같은 논문을 둘로
    센다(norm_id 규약 1조가 제목 기준을 기각한 이유). 여기서는 **최후 폴백**으로만
    쓰되, 정규화를 강하게 걸어 표기 변형을 흡수한다.
    """
    if x is None:
        return ''
    import unicodedata
    s = unicodedata.normalize('NFKC', str(x)).lower()
    s = re.sub(r'[^0-9a-z가-힣]+', ' ', s)
    return re.sub(r'\s+', ' ', s).strip()


def title_hash(x):
    """정규화 제목의 sha1 앞 12자. 제목 판별 불가면 ''."""
    t = norm_title(x)
    if not t:
        return ''
    import hashlib
    return hashlib.sha1(t.encode('utf-8')).hexdigest()[:12]


def paper_key(arxiv_id=None, doi=None, title=None, source_url=None):
    """중복 방지 정본 키. 3단 우선순위(axv > doi > ttl), 판별 불가면 ''."""
    ax = arxiv_id_from(arxiv_id) or arxiv_id_from(source_url)
    if ax:
        return 'axv:' + ax
    d = norm_doi(doi) or norm_doi(source_url)
    if d:
        return 'doi:' + d
    th = title_hash(title)
    if th:
        return 'ttl:' + th
    return ''


_REGISTRY_REL = os.path.join('06_Registry', 'paper_registry.json')


def default_registry_path():
    """paper_registry.json 정본 경로 (env `QVEST_PAPER_REGISTRY` 로 오버라이드)."""
    env = os.environ.get('QVEST_PAPER_REGISTRY')
    if env:
        return env
    return os.path.join(_project_root(), _REGISTRY_REL)


def entry_paper_key(e):
    """registry/route 항목(dict)에서 paper_key 계산. 저장된 paper_key 우선."""
    if not isinstance(e, dict):
        return ''
    pk = str(e.get('paper_key') or '').strip()
    if pk:
        return pk
    return paper_key(arxiv_id=e.get('arxiv_id'), doi=e.get('doi'),
                     title=e.get('title'), source_url=e.get('source'))


def registry_keys(path=None):
    """registry 전건의 paper_key 집합. 부재 시 빈 집합(수집 자체를 막지 않는다)."""
    p = path or default_registry_path()
    if not os.path.exists(p):
        return set()
    with io.open(p, 'r', encoding='utf-8-sig') as fh:
        arr = json.load(fh)
    out = set()
    if isinstance(arr, list):
        for e in arr:
            k = entry_paper_key(e)
            if k:
                out.add(k)
    return out


def _cli_keys_batch(argv):
    """keys-batch <in.json> [--registry <path>] [--out <path>]

    입력  = [{arxiv_id?, doi?, title?, source?}, …] (paper_recharge 후보 목록)
    출력  = {"keys": [...], "in_registry": [...], "n_registry": N}
            keys[i] 는 입력 i 번째 항목의 paper_key('' 가능), in_registry[i] 는
            registry 기존재 여부. R 수집기가 이 1회 호출로 dedup 을 끝낸다
            (R 이 규약을 재구현하지 않는다 — 정본은 이 파일 하나).
    """
    if not argv or argv[0].startswith('--'):
        sys.stderr.write('usage: paper_id_norm.py keys-batch <in.json>'
                         ' [--registry <path>] [--out <path>]\n')
        return 2

    def opt(name, default=None):
        flag = '--' + name
        if flag in argv:
            i = argv.index(flag)
            if i + 1 < len(argv):
                return argv[i + 1]
            raise SystemExit('%s 에 값이 없습니다' % flag)
        return default

    with io.open(argv[0], 'r', encoding='utf-8-sig') as fh:
        items = json.load(fh)
    if not isinstance(items, list):
        raise SystemExit('keys-batch 입력은 배열이어야 합니다')
    reg = registry_keys(opt('registry'))
    keys, hits = [], []
    for e in items:
        k = entry_paper_key(e) if isinstance(e, dict) else ''
        keys.append(k)
        hits.append(bool(k) and k in reg)
    payload = json.dumps({'keys': keys, 'in_registry': hits,
                          'n_registry': len(reg)}, ensure_ascii=False)
    out = opt('out')
    if out:
        _atomic_write(out, payload + '\n')
    else:
        print(payload)
    return 0


# ── 소비 원장 append (2026-08-23 신설, v9 Lean Loop §3.4(e)) ──────────────────
#   왜 여기인가: 원장을 **손편집**하던 프롬프트 2종이 배열을 조기에 닫아
#   `LEDGER_UNREADABLE` 을 만들었다(2026-08-09 · 2026-08-23 두 번). 손편집을 없애려면
#   호출 가능한 append 가 있어야 하고, id 정규화 정본이 이미 여기 있으므로 여기에 둔다.
#   ★계약 3줄:
#     1. 읽기는 BOM 관용(`utf-8-sig`) — 생산자 중 BOM 을 쓰는 계열이 실재한다.
#     2. 쓰기는 **tmp + os.replace** 원자 교체 — 중단된 쓰기가 원장을 파손하지 않는다.
#     3. 쓰기 직전 **재파싱 검증** — 검증 실패 시 원본을 건드리지 않고 예외를 던진다.

_LEDGER_REL = os.path.join('stage_artifacts', 'paper_recharge',
                           'alpha_search_queue_done.json')

# 레코드 기본 골격 — 기존 31건이 공유하는 9개 필드의 순서를 그대로 따른다.
_CORE_ORDER = ('paper_id', 'paper_title', 'factor_id', 'factor_name',
               'strategy_id', 'gate_decision', 'gate_failed_layers',
               'screen_route', 'port_t', 'grade', 'processed_date',
               'verify_path', 'bt_result_dir')


def _project_root():
    """저장소 루트. **self-first** — 이 파일 위치에서 올라간다.

    ★`QM_ROOT` 를 먼저 보지 않는 이유: User scope 에 main 이 pin 돼 있어 워크트리에서
      실행해도 main 을 가리킨다(2026-08-21 실측). 자기 위치가 유일하게 정직한 좌표다.
    """
    return os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))


def default_ledger_path():
    """소비 원장 정본 경로."""
    env = os.environ.get('QVEST_ALPHA_DONE_LEDGER')
    if env:
        return env
    return os.path.join(_project_root(), _LEDGER_REL)


def load_ledger(ledger_path=None):
    """원장을 BOM 관용으로 읽는다. 부재면 빈 골격(있는 척하지 않되 append 는 가능)."""
    path = ledger_path or default_ledger_path()
    if not os.path.exists(path):
        return {'processed': [], 'records': [], 'last_updated': ''}
    with io.open(path, 'r', encoding='utf-8-sig') as fh:
        obj = json.load(fh)
    if not isinstance(obj, dict):
        raise ValueError('ledger top-level is %s, expected object'
                         % type(obj).__name__)
    obj.setdefault('processed', [])
    obj.setdefault('records', [])
    return obj


def _validate(obj):
    """쓰기 직전 검증 — 여기서 막지 못하면 다음 소비자가 LEDGER_UNREADABLE 을 본다."""
    if not isinstance(obj.get('processed'), list):
        raise ValueError('processed must be a list')
    if not isinstance(obj.get('records'), list):
        raise ValueError('records must be a list')
    for i, x in enumerate(obj['processed']):
        if not isinstance(x, str) or not x.strip():
            raise ValueError('processed[%d] is not a non-empty string' % i)
    for i, r in enumerate(obj['records']):
        if not isinstance(r, dict):
            raise ValueError('records[%d] is not an object' % i)
        if not str(r.get('paper_id') or '').strip():
            raise ValueError('records[%d] has no paper_id' % i)
    # 직렬화 왕복 — 실제로 다시 읽히는지까지 확인한다.
    return json.loads(json.dumps(obj, ensure_ascii=False))


def _detect_eol(path):
    """기존 줄끝을 그대로 잇는다 — 원장 전체가 줄끝만으로 diff 나는 것을 막는다."""
    try:
        with io.open(path, 'rb') as fh:
            head = fh.read(4096)
        return '\r\n' if b'\r\n' in head else '\n'
    except Exception:
        return '\n'


def _atomic_write(path, text, eol='\n'):
    tmp = path + '.tmp'
    with io.open(tmp, 'w', encoding='utf-8', newline=eol) as fh:
        fh.write(text)
    os.replace(tmp, path)


def append_done_record(paper_id, gate_decision, strategy_id=None,
                       screen_route=None, processed_date=None, extra=None,
                       ledger_path=None):
    """소비 원장에 1건 append. 반환 = 기록된 레코드(dict).

    · paper_id 는 `norm_id()` 정본으로 정규화된 뒤에 저장·비교된다.
    · `processed[]` 는 집합 의미이므로 이미 있으면 다시 넣지 않는다(레코드는 항상 append
      — 같은 논문에서 팩터를 여럿 뽑는 감사 로그가 실재한다, schema_note 참조).
    · `extra` 는 자유 필드(paper_title / next_probe / l_code …)를 그대로 병합한다.
    """
    pid = norm_id(paper_id)
    if not pid:
        raise ValueError('paper_id 가 비었거나 정규화 불가: %r' % (paper_id,))
    gate = str(gate_decision or '').strip()
    if not gate:
        raise ValueError('gate_decision 은 필수다 (ADOPT/SCREEN_TIER/QUARANTINE/…)')

    path = ledger_path or default_ledger_path()
    obj = load_ledger(path)

    if processed_date is None:
        import datetime
        processed_date = datetime.datetime.now().strftime('%Y%m%d')

    rec = {}
    payload = dict(extra or {})
    rec['paper_id'] = pid
    rec['paper_title'] = payload.pop('paper_title', None)
    rec['factor_id'] = payload.pop('factor_id', None)
    rec['factor_name'] = payload.pop('factor_name', None)
    rec['strategy_id'] = strategy_id
    rec['gate_decision'] = gate
    rec['gate_failed_layers'] = payload.pop('gate_failed_layers', None)
    rec['screen_route'] = screen_route
    rec['port_t'] = payload.pop('port_t', None)
    rec['grade'] = payload.pop('grade', None)
    rec['processed_date'] = str(processed_date)
    rec['verify_path'] = payload.pop('verify_path', None)
    rec['bt_result_dir'] = payload.pop('bt_result_dir', None)
    for k, v in payload.items():
        if k not in _CORE_ORDER:
            rec[k] = v

    existing = {norm_id(x) for x in obj['processed'] if norm_id(x)}
    if pid not in existing:
        obj['processed'].append(pid)
    obj['records'].append(rec)
    obj['last_updated'] = str(processed_date)

    checked = _validate(obj)
    _atomic_write(path, json.dumps(checked, ensure_ascii=False, indent=2) + '\n',
                  eol=_detect_eol(path))
    return rec


def _cli_append_done(argv):
    """append-done --paper-id … --gate … [--strategy-id …] [--screen-route …]"""
    def opt(name, default=None):
        flag = '--' + name
        if flag in argv:
            i = argv.index(flag)
            if i + 1 < len(argv):
                return argv[i + 1]
            raise SystemExit('%s 에 값이 없습니다' % flag)
        return default

    pid = opt('paper-id')
    gate = opt('gate')
    if not pid or not gate:
        sys.stderr.write(
            'usage: paper_id_norm.py append-done --paper-id <id> --gate <decision>\n'
            '           [--strategy-id <id>] [--screen-route <route>]\n'
            '           [--processed-date <YYYYMMDD>] [--title <t>] [--grade <g>]\n'
            '           [--port-t <x>] [--verify-path <p>] [--bt-result-dir <p>]\n'
            '           [--note <text>] [--ledger <path>]\n')
        return 2
    extra = {}
    for flag, key in (('title', 'paper_title'), ('grade', 'grade'),
                      ('port-t', 'port_t'), ('verify-path', 'verify_path'),
                      ('bt-result-dir', 'bt_result_dir'),
                      ('factor-name', 'factor_name'), ('note', 'session_note')):
        v = opt(flag)
        if v is not None:
            if key == 'port_t':
                try:
                    v = float(v)
                except ValueError:
                    pass
            extra[key] = v
    rec = append_done_record(pid, gate,
                             strategy_id=opt('strategy-id'),
                             screen_route=opt('screen-route'),
                             processed_date=opt('processed-date'),
                             extra=extra or None,
                             ledger_path=opt('ledger'))
    print('[append-done] %s → %s (strategy=%s, screen_route=%s)'
          % (rec['paper_id'], rec['gate_decision'], rec['strategy_id'],
             rec['screen_route']))
    return 0


if __name__ == '__main__' and len(sys.argv) > 1 and sys.argv[1] == 'append-done':
    raise SystemExit(_cli_append_done(sys.argv[2:]))

if __name__ == '__main__' and len(sys.argv) > 1 and sys.argv[1] == 'keys-batch':
    raise SystemExit(_cli_keys_batch(sys.argv[2:]))

if __name__ == '__main__':
    cases = [
        ('arxiv:2607.19497', '2607.19497'),
        ('arXiv:2607.19497v2', '2607.19497'),
        ('2607.19497', '2607.19497'),
        ('  2607.19497v11  ', '2607.19497'),
        ('https://arxiv.org/abs/2606.08569', '2606.08569'),
        ('FQ-110B', 'FQ-110B'),                 # 내부 id 는 훼손 금지
        ('some_paper_v2.pdf', 'some_paper_v2'),  # curated: 확장자만
        ('', ''),
        (None, ''),
    ]
    bad = 0
    for raw, want in cases:
        got = norm_id(raw)
        mark = 'ok  ' if got == want else 'FAIL'
        if got != want:
            bad += 1
        print('%s %-34r → %-16r (기대 %r)' % (mark, raw, got, want))

    # paper_key 3단 (v10) — 함수·우선순위 자체검사
    key_cases = [
        (dict(arxiv_id='arXiv:2202.03012v2'), 'axv:2202.03012'),
        (dict(source_url='https://arxiv.org/pdf/2608.25223'), 'axv:2608.25223'),
        (dict(source_url='https://arxiv.org/pdf/2202.03012v2.pdf'), 'axv:2202.03012'),
        (dict(doi='https://doi.org/10.1111/J.1540-6261.1993.TB04702.X'),
         'doi:10.1111/j.1540-6261.1993.tb04702.x'),
        (dict(arxiv_id='2607.19497', doi='10.2139/ssrn.123'), 'axv:2607.19497'),
        (dict(title='Returns to Buying Winners and Selling Losers:  '
                    'Implications…'), 'ttl:' + title_hash(
                        'returns to buying winners and selling losers implications')),
        (dict(title='  '), ''),
        (dict(), ''),
    ]
    for kw, want in key_cases:
        got = paper_key(**{('source_url' if k == 'source_url' else k): v
                           for k, v in kw.items()})
        mark = 'ok  ' if got == want else 'FAIL'
        if got != want:
            bad += 1
        print('%s paper_key(%r) → %r (기대 %r)' % (mark, kw, got, want))

    print('\n%d/%d' % (len(cases) + len(key_cases) - bad, len(cases) + len(key_cases)))
    raise SystemExit(1 if bad else 0)
