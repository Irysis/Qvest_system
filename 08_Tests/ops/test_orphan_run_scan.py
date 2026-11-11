# -*- coding: utf-8 -*-
"""test_orphan_run_scan.py — 무음 사망 탐지의 **구간·보류·검출력** (2026-08-22 신설)

왜 있나 (실사고 2026-08-22 18:30):
  qepm_dossier 런이 WT-D20260813_001 을 9일 만에 ALPHA_DONE 으로 올린 뒤
  19:29 이후 **흔적 없이 사라졌다** — `claude -p exit=` 0건, 완주 알림 미발화,
  락은 trap 이 정상 해제. 다음 런은 아무 이상을 못 느끼고 시작했다.
  정체 경보는 이걸 못 잡는다 — 그 장치는 **살아서 매달린** 홀더를 겨누는데,
  죽은 런은 락을 반납하므로 경합 자체가 안 생겨 검사가 실행되지 않는다.

★이 검사의 축 3개:
  ① **구간**: 각 start 부터 다음 start 직전까지만 본다. 파일 전체를 훑으면
     이전 런의 종료가 현재 런의 종료로 읽힌다(오늘 하루 4회 틀린 그 계통).
  ② **보류**: 진행 중인 런을 무음 사망으로 세지 않는다. 세기 전에 분모를 정한다.
  ③ **검출력**: 진짜 무짝을 잡고, 정상 종료를 잡지 않는다(양방향).
"""
import io
import os
import subprocess
import sys
import tempfile
import shutil
import datetime
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCAN = os.path.join(ROOT, '02_Infrastructure', 'ops', 'orphan_run_scan.py')
# ★인터프리터 해석: 자기 자신을 기본으로 쓴다. QVEST_PY 는 상대경로일 수 있어
#   subprocess 가 못 찾는다(실측: WinError 2). **존재를 확인한 뒤에만** 쓴다.
_qp = os.environ.get('QVEST_PY') or ''
PY = _qp if (_qp and os.path.isabs(_qp) and os.path.exists(_qp)) else sys.executable

_p = [0]
_f = [0]


def ok(m):
    _p[0] += 1
    print("  PASS  %s" % m)


def ng(m, d):
    _f[0] += 1
    print("  FAIL  %s :: %s" % (m, d))


def run(root, *extra):
    cmd = [PY, SCAN, root] + list(extra)
    r = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace')
    return (r.stdout or '') + (r.stderr or '')


def mkfix(lines):
    d = tempfile.mkdtemp()
    os.makedirs(os.path.join(d, '.cache', 'scheduler_logs'))
    io.open(os.path.join(d, '.cache', 'scheduler_logs', 'x_20260822.log'),
            'w', encoding='utf-8').write("\n".join(lines) + "\n")
    return d


def ts(minutes_ago):
    t = datetime.datetime.now() - datetime.timedelta(minutes=minutes_ago)
    return t.strftime('%Y-%m-%dT%H:%M:%S+09:00')


if not os.path.exists(SCAN):
    print("  SKIP  스캐너 부재")
    print("== t_summary: PASS=0 FAIL=0 ==")
    print('{"test":"orphan_run_scan","pass":0,"fail":0,"total":0,"skipped":1,"skips":[{"axis":"ALL","reason":"스캐너 부재","missing":"%s"}]}' % (SCAN))
    sys.exit(0)

print("== 양성 대조: 정상 종료한 런을 무음 사망으로 세지 않는가 ==")
d = mkfix(["%s [router] start (x)" % ts(500),
           "%s [router] claude -p exit=0" % ts(495)])
out = run(d)
shutil.rmtree(d, ignore_errors=True)
if "무음 사망 의심): 0건" in out:
    ok("정상 종료 → 0건")
else:
    ng("정상 종료 오탐", out.strip().splitlines()[:3])

print("== 검출력: start 만 있고 종료가 없으면 잡는가 (실사고 재현) ==")
d = mkfix(["%s [modeq] start (pending=70)" % ts(500),
           "%s [modeq] 토큰 지문: abc" % ts(499)])
out = run(d)
shutil.rmtree(d, ignore_errors=True)
if "무음 사망 의심): 1건" in out:
    ok("무짝 start → 1건")
else:
    ng("무짝 미검출", out.strip().splitlines()[:3])

print("== ★구간 축: 이전 런의 종료를 현재 런의 종료로 읽지 않는가 ==")
# 파일 전체를 훑으면 첫 exit 이 두 번째 start 의 종료로 읽혀 0건이 된다.
d = mkfix(["%s [router] start (1회차)" % ts(600),
           "%s [router] claude -p exit=0" % ts(595),
           "%s [router] start (2회차)" % ts(500),
           "%s [router] 토큰 지문: abc" % ts(499)])
out = run(d)
shutil.rmtree(d, ignore_errors=True)
if "무음 사망 의심): 1건" in out:
    ok("구간 분리 — 2회차만 무짝으로 검거")
else:
    ng("구간 미분리", "이전 런의 exit 을 현재 종료로 읽는다: %s" % out.strip().splitlines()[:3])

print("== ★보류 축: 진행 중인 런을 무음 사망으로 세지 않는가 ==")
d = mkfix(["%s [modeq] start (진행중)" % ts(5),
           "%s [modeq] 토큰 지문: abc" % ts(4)])
out = run(d)
if "무음 사망 의심): 0건" in out and "진행 중 1건 보류" in out:
    ok("최근 런 → 보류 (오탐 방지)")
else:
    ng("보류 미작동", out.strip().splitlines()[:2])

print("== 보류 문턱이 실효인가 (grace 축소 시 잡혀야) ==")
out = run(d, '--grace', '1')
shutil.rmtree(d, ignore_errors=True)
if "무음 사망 의심): 1건" in out:
    ok("grace 1분 → 같은 런이 무짝으로 전환 (문턱 실효)")
else:
    ng("grace 무시", out.strip().splitlines()[:2])

print("== 종료 신호 다양성: skip/DRYRUN 도 종료로 인정하는가 ==")
d = mkfix(["%s [router] start (x)" % ts(500),
           "%s [router] DRYRUN — claude 미호출" % ts(499)])
out = run(d)
shutil.rmtree(d, ignore_errors=True)
if "무음 사망 의심): 0건" in out:
    ok("DRYRUN → 종료로 인정 (오탐 방지)")
else:
    ng("종료 신호 협소", "정상 skip 을 사망으로 신고한다")

print("== 상태라인: 0건일 때와 N건일 때 문구가 갈리는가 ==")
d = mkfix(["%s [router] start" % ts(500), "%s [router] claude -p exit=0" % ts(499)])
out = run(d, '--status-line')
shutil.rmtree(d, ignore_errors=True)
if "무음 사망 0건" in out:
    ok("0건 → 무해 문구")
else:
    ng("상태라인 0건", out.strip())

d = mkfix(["%s [modeq] start" % ts(500), "%s [modeq] 토큰" % ts(499)])
out = run(d, '--status-line')
shutil.rmtree(d, ignore_errors=True)
if "★" in out and "1건" in out:
    ok("N건 → ★ 강조 + 러너 이름 노출")
else:
    ng("상태라인 N건", out.strip())

print("== ★창 축(11-11): 이름순으로는 뒤지만 날짜는 오래된 로그가 많아도 최근 로그를 보는가 ==")
# 구판 결함: sorted(glob)[-N:] = 이름순 마지막 N개 → 이름이 뒤쪽(zz_)인 옛 로그가 창을 채워 최근(a_) 로그를 놓쳤다.
# --days 1 → 창 = max(6, 20) = 20개. 옛 로그 25개(이름 zz_ · 2026-01 날짜 · 정상 종료)를 깔고 최근 무짝 2개를 둔다:
#   a_recent_<오늘>.log(이름 속 날짜) · ab_undated.log(이름에 날짜 없음 → 수정 시각 = 지금).
#   이름에 날짜 없고 수정 시각이 옛날인 zzzz_undated_old.log 의 무짝은 창 밖이어야 한다(수정 시각 대체의 반대 방향).
d = tempfile.mkdtemp()
_ld = os.path.join(d, '.cache', 'scheduler_logs')
os.makedirs(_ld)
def _wl(name, lines, mtime=None):
    p = os.path.join(_ld, name)
    io.open(p, 'w', encoding='utf-8').write("\n".join(lines) + "\n")
    if mtime is not None:
        os.utime(p, (mtime, mtime))
_old = datetime.datetime(2026, 1, 1, 12, 0, 0)
for i in range(25):
    t0 = _old + datetime.timedelta(days=i)
    _wl('zz_old_%s.log' % t0.strftime('%Y%m%d'),
        ["%s [router] start (옛)" % t0.strftime('%Y-%m-%dT%H:%M:%S+09:00'),
         "%s [router] claude -p exit=0" % t0.strftime('%Y-%m-%dT%H:%M:%S+09:00')],
        mtime=time.mktime(t0.timetuple()))
_wl('a_recent_%s.log' % datetime.datetime.now().strftime('%Y%m%d'),
    ["%s [modeq] start (최근 · 이름 속 날짜)" % ts(500), "%s [modeq] 토큰 지문: abc" % ts(499)])
_wl('ab_undated.log',
    ["%s [recheck] start (최근 · 날짜 없는 이름)" % ts(400), "%s [recheck] 토큰 지문: abc" % ts(399)])
_wl('zzzz_undated_old.log',
    ["%s [alpha_queue] start (옛 · 날짜 없는 이름)" % "2025-06-01T10:00:00+09:00"],
    mtime=time.mktime(datetime.datetime(2025, 6, 1, 10, 0, 0).timetuple()))
out = run(d, '--days', '1')
shutil.rmtree(d, ignore_errors=True)
if ("스캔 로그 20개" in out and "무음 사망 의심): 2건" in out and "modeq 1" in out and "recheck 1" in out
        and "alpha_queue" not in out):
    ok("날짜순 창 — 이름 뒤쪽 옛 로그 25개 속에서 최근 무짝 2건(이름 속 날짜 · 수정 시각) 검거 · 옛 수정 시각 로그는 창 밖")
else:
    ng("창이 날짜순이 아니다", out.strip().splitlines()[:8])

print("== 실 저장소 축: 08-22 18:30 사건이 실제로 잡히는가 ==")
# 11-11: 창을 사건 날짜까지 덮게 잡는다. 구판 '--days 30' 은 사건 뒤 30일이 지나면(10월부터) 창 밖이라
#   이 단언이 날짜만으로 빨개졌다 — 지키려는 성질(실로그 형식에서 실사고를 잡는다)은 그대로 두고 창만 사건에 맞춘다.
_incident_days = (datetime.date.today() - datetime.date(2026, 8, 22)).days + 1
out = run(ROOT, '--days', str(max(30, _incident_days)))
if "2026-08-22T18:30:58" in out and "modeq" in out:
    ok("실사고 18:30 modeq 런 검거")
elif "무음 사망 의심): 0건" in out:
    ng("실 저장소 미검출", "18:30 런이 안 잡힌다 — 로그가 정리됐거나 패턴 불일치")
else:
    ok("실 저장소 스캔 동작 (18:30 건은 로그 상태에 따라 변동)")

print("== t_summary: PASS=%d FAIL=%d ==" % (_p[0], _f[0]))
print('{"test":"orphan_run_scan","pass":%d,"fail":%d,"total":%d,"skipped":0}' % (_p[0], _f[0], (_p[0])+(_f[0])))
sys.exit(1 if _f[0] else 0)
