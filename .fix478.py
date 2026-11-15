p='watchman/FINDER_QUEUE.md'
s=open(p).read()
a='a later snapshot of the same market must show a book, else the trade is void and counted;'
b='no trade is voided or dropped for what happens after entry (that would be look-ahead; a taker at the touch fills at once), but trades whose next snapshot is suspended or after a second goal are counted and shown apart;'
c='local copy now 31 Oct-8 Nov 15:03'
d='local copy now 31 Oct to 8 Nov about 14:03 UTC (DB clock 15:03)'
assert s.count(a)==1 and s.count(c)==1
s=s.replace(a,b).replace(c,d); open(p,'w').write(s); print('ok')
