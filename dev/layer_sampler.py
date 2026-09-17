"""Sample one process's Hyprland layer surfaces as fast as the socket answers.

    python3 dev/layer_sampler.py <pid> <seconds> <out file>

Writes a line whenever the set changes: "<ms> <namespace> <address> <w>x<h>@<x>,<y> | ...",
and a final "samples <n> over <s>s". Used by dev/surface.sh to prove no surface showing the
notch is ever resized or recreated (Hyprland draws a resized layer's old buffer stretched for
a few frames, which blinks).
"""
import socket, os, sys, time, json
pid=int(sys.argv[1]); dur=float(sys.argv[2]); out=open(sys.argv[3],'w')
p=os.path.join(os.environ['XDG_RUNTIME_DIR'],'hypr',os.environ['HYPRLAND_INSTANCE_SIGNATURE'],'.socket.sock')
end=time.time()+dur; last=None; n=0
while time.time()<end:
    s=socket.socket(socket.AF_UNIX); s.connect(p); s.sendall(b'j/layers')
    buf=b''
    while True:
        d=s.recv(65536)
        if not d: break
        buf+=d
    s.close(); n+=1
    t=time.time()
    try: data=json.loads(buf)
    except Exception: continue
    cur=[]
    for mon in data.values():
        for lvl in mon['levels'].values():
            for l in lvl:
                if l['pid']==pid: cur.append("%s %s %dx%d@%d,%d"%(l['namespace'],l['address'],l['w'],l['h'],l['x'],l['y']))
    cur=sorted(cur)
    if cur!=last:
        out.write("%d %s\n"%(int(t*1000)," | ".join(cur))); out.flush(); last=cur
out.write("samples %d over %.1fs\n"%(n,dur))
