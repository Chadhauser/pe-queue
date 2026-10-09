"""Shared credential lookup for queue jobs. Reads what is ALREADY on this server, in this order:
process environment -> /etc/environment -> ~/.bashrc, ~/.profile, ~/.bash_profile (export lines) -> .env files under /root/pe-* ->
module constants in /root/pe-bot/bot_core.py. Never prints values."""
import os, re, glob, sys
def _file_vars(path):
    d={}
    try:
        for ln in open(path, errors='ignore'):
            m=re.match(r'^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$', ln)
            if m and not ln.lstrip().startswith('#'):
                v=m.group(2).strip().strip('"').strip("'")
                if v and v not in ('VALUE','PASTE_KEY_HERE','PASTE_HERE'): d.setdefault(m.group(1), v)
    except Exception: pass
    return d
def all_vars():
    d=dict(os.environ)
    for f in ['/etc/environment', os.path.expanduser('~/.bashrc'), os.path.expanduser('~/.profile'), os.path.expanduser('~/.bash_profile'),
              os.path.expanduser('~/.pam_environment')] + glob.glob('/root/pe-*/.env*') + glob.glob('/root/*/.env'):
        for k,v in _file_vars(f).items(): d.setdefault(k, v)
    try:
        sys.path.insert(0,'/root/pe-bot'); import bot_core
        for k in dir(bot_core):
            if k.isupper() and isinstance(getattr(bot_core,k), str): d.setdefault(k, getattr(bot_core,k))
    except Exception: pass
    return d
def first(d, names):
    for n in names:
        if d.get(n): return d[n]
    return None
def betfair():
    d=all_vars()
    app=first(d,['BETFAIR_APP_KEY','BF_APP_KEY','APP_KEY','BETFAIR_APPKEY'])
    user=first(d,['BETFAIR_USERNAME','BETFAIR_USER','BF_USERNAME','BF_USER','USERNAME'])
    pw=first(d,['BETFAIR_PASSWORD','BETFAIR_PASS','BF_PASSWORD','BF_PASS','PASSWORD'])
    return app,user,pw
def apifootball():
    d=all_vars()
    return first(d,['API_FOOTBALL_KEY','APIFOOTBALL_KEY','APISPORTS_KEY','API_SPORTS_KEY','RAPIDAPI_KEY','X_RAPIDAPI_KEY'])
def report():
    app,user,pw=betfair(); k=apifootball()
    return f"betfair app_key={'yes' if app else 'NO'} username={'yes' if user else 'NO'} password={'yes' if pw else 'NO'} | api-football key={'yes' if k else 'NO'}"
if __name__=='__main__': print(report())
