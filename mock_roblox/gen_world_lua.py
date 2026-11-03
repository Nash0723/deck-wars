# Converts the Rojo model JSON into a Luau builder that uses the mock datatypes (type-aware via the reflection DB).
import json, msgpack, glob, sys
import os
# Roblox's API list comes with Rojo's crates (run `cargo install rojo --locked` once)
_cargo = os.environ.get('CARGO_HOME', os.path.expanduser('~/.cargo'))
_found = sorted(glob.glob(os.path.join(_cargo, 'registry', 'src', '*', 'rbx_reflection_database-*', 'database.msgpack')))
if not _found: sys.exit('Roblox API list not found: run `cargo install rojo --locked` first')
p = _found[-1]
db=msgpack.unpackb(open(p,'rb').read(), raw=False, strict_map_key=False)
classes=db[1]
def ptype(cls, prop):
    c=cls
    while c:
        d=classes[c]
        if prop in d[3]:
            t=d[3][prop][2]
            return ("Enum:"+t['Enum']) if 'Enum' in t else t.get('Value')
        c=d[2]
    raise SystemExit(f"Unknown property {cls}.{prop}")
def lua(v, t):
    if t=="Vector3": return f"Vector3.new({v[0]},{v[1]},{v[2]})"
    if t=="Vector2": return f"Vector2.new({v[0]},{v[1]})"
    if t=="Color3": return f"Color3.new({v[0]},{v[1]},{v[2]})"
    if t=="CFrame":
        c=v["CFrame"]; pos=c["position"]; o=c["orientation"]
        return f"CFrame.new({pos[0]},{pos[1]},{pos[2]},{o[0][0]},{o[0][1]},{o[0][2]},{o[1][0]},{o[1][1]},{o[1][2]},{o[2][0]},{o[2][1]},{o[2][2]})"
    if t=="UDim2":
        (xs,xo),(ys,yo)=v["UDim2"]; return f"UDim2.new({xs},{xo},{ys},{yo})"
    if t and t.startswith("Enum:"): return f'Enum.{t[5:]}.{v}'
    if isinstance(v,bool): return "true" if v else "false"
    if isinstance(v,(int,float)): return repr(v)
    if isinstance(v,str): return json.dumps(v)
    raise SystemExit(f"cannot convert {v} as {t}")
def node(n, ind="\t"):
    cls=n["ClassName"]; props=n.get("Properties",{})
    parts=[f'ClassName={json.dumps(cls)}', f'Name={json.dumps(n.get("Name",cls))}']
    pl=[]
    for k,v in props.items():
        pl.append(f'{k}={lua(v, ptype(cls,k))}')
    parts.append("Properties={"+",".join(pl)+"}")
    kids=[node(c, ind+"\t") for c in n.get("Children",[])]
    parts.append("Children={"+",".join(kids)+"}")
    return "{"+", ".join(parts)+"}"
src=json.load(open(sys.argv[1]))
open(sys.argv[2],"w").write("return function()\n\treturn "+node(src)+"\nend\n")
print("ok")
