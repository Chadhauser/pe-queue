import re
def tail(p, n=200):
    with open(p, 'rb') as f:
        f.seek(0, 2); sz = f.tell(); f.seek(max(0, sz - 400000))
        return f.read().decode('utf8', 'replace').splitlines()[-n:]
s = tail('/root/pe-stream/stream.log', 300)
print('stream 400s in last 300 lines:', sum(' 400' in l for l in s))
mk = [l for l in s if re.search(r'markets?\W*\d+', l, re.I)]
print('stream last market-count lines:'); [print('  ', l[:160]) for l in mk[-3:]]
print('stream last line:', s[-1][:160] if s else None)
pl = tail('/root/pe-player/player.log', 200)
print('player KeyError in last 200:', sum('KeyError' in l for l in pl)); print('player last:', pl[-1][:160] if pl else None)
lq = tail('/root/pe-liq/recorder.log', 300)
print('liq TOO_MUCH_DATA in last 300:', sum('TOO_MUCH_DATA' in l for l in lq)); print('liq last:', lq[-1][:160] if lq else None)
