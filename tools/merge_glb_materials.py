#!/usr/bin/env python3
"""Merge same-material leaf nodes within a split stadium GLB (PS4 draw-call budget).

The stadium leaf nodes are identity transforms parented directly to the scene
group, so all meshes sharing one material can be concatenated into a single
mesh (one draw call). Hidden leaves listed in modern_stadium.tscn are NEVER
merged, so visibility overrides keep resolving. Requires float32 POSITION and
per-accessor bufferViews (i.e. gltfpack -vpf + unpack_views.py output).

Usage: python3 tools/merge_glb_materials.py <in.glb> <out.glb>
"""
import struct
import json
import sys
import array

COMP_FMT = {5126: "f", 5125: "I", 5123: "H", 5121: "B", 5120: "b", 5122: "h"}
NCOMP = {"VEC2": 2, "VEC3": 3, "VEC4": 4, "SCALAR": 1}

# Leaves hidden via node overrides in stadiums/modern_stadium/modern_stadium.tscn
# (gltf dot naming). These must stay as individual nodes.
HIDDEN = {
    "Material2.136", "Material3.035", "Material2.140", "Material3.036",
    "Material3.037", "Material2.144", "Material3.034", "Material2.139",
    "Material2.141", "Material3.038", "Material2.133",
}


def read_glb(path):
    with open(path, "rb") as f:
        magic, version, total = struct.unpack("<4sII", f.read(12))
        assert magic == b"glTF", magic
        clen, ctype = struct.unpack("<I4s", f.read(8))
        assert ctype == b"JSON"
        data = json.loads(f.read(clen).decode("utf-8"))
        clen, ctype = struct.unpack("<I4s", f.read(8))
        assert ctype == b"BIN\0"
        blob = bytearray(f.read(clen))
    return data, blob


def acc_array(data, blob, a_idx):
    acc = data["accessors"][a_idx]
    bv = data["bufferViews"][acc["bufferView"]]
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    n = acc["count"] * NCOMP[acc["type"]]
    arr = array.array(COMP_FMT[acc["componentType"]])
    arr.frombytes(bytes(blob[off:off + n * arr.itemsize]))
    if sys.byteorder != "little":
        arr.byteswap()
    return arr


def merge(inp, outp):
    data, blob = read_glb(inp)
    nodes = data["nodes"]
    meshes = data["meshes"]

    gi = next(i for i, n in enumerate(nodes) if n.get("name", "").startswith("Collada"))
    group = nodes[gi]
    children = list(group["children"])

    # 1. classify children: mergeable leaf or kept node
    def mergeable(c):
        n = nodes[c]
        if n.get("mesh") is None or n.get("name", "") in HIDDEN:
            return False
        if any(k in n for k in ("translation", "rotation", "scale", "matrix")):
            return False
        m = meshes[n["mesh"]]
        if len(m["primitives"]) != 1:
            return False
        p = m["primitives"][0]
        return "indices" in p and "targets" not in p and p.get("mode", 4) == 4

    groups = {}       # material -> list of child indices (in order)
    kept = set(range(len(children)))
    for pos, c in enumerate(children):
        if not mergeable(c):
            continue
        mat = meshes[nodes[c]["mesh"]]["primitives"][0].get("material")
        groups.setdefault(mat, []).append(pos)
    # only merge groups whose members all share an identical attribute set
    merged_groups = {}
    for mat, ps in groups.items():
        if len(ps) < 2:
            continue
        keysets = {tuple(sorted(meshes[nodes[children[p]]["mesh"]]["primitives"][0]["attributes"])) for p in ps}
        if len(keysets) == 1:
            merged_groups[mat] = ps
        else:
            print(f"  note: material {mat} has mixed attribute sets, keeping {len(ps)} nodes separate")
    for ps in merged_groups.values():
        kept -= set(ps)

    def add_view(payload, target):
        nonlocal blob
        while len(blob) % 4:
            blob += b"\x00"
        off = len(blob)
        v = len(data["bufferViews"])
        blob.extend(payload)
        data["bufferViews"].append({"buffer": 0, "byteOffset": off,
                                    "byteLength": len(payload), "target": target})
        return v

    def append_accessor(v, src_acc, count, key=None, arr=None):
        a = {"bufferView": v, "componentType": src_acc["componentType"],
             "count": count, "type": src_acc["type"]}
        if key == "POSITION" and arr is not None:
            nc = NCOMP[src_acc["type"]]
            a["min"] = [min(arr[i::nc]) for i in range(nc)]
            a["max"] = [max(arr[i::nc]) for i in range(nc)]
        data["accessors"].append(a)
        return len(data["accessors"]) - 1

    new_children = []
    total_saved = 0
    emitted = set()
    for pos, c in enumerate(children):
        if pos in kept:
            new_children.append(c)
            continue
        # find which merge group this pos belongs to
        mat = next(m for m, ps in merged_groups.items() if pos in ps)
        if mat in emitted:
            continue
        emitted.add(mat)
        ps = merged_groups[mat]
        out_attr = {}
        out_idx = array.array("I")
        vbase = 0
        names = []
        src_tpl = {}
        for q in ps:
            n = nodes[children[q]]
            names.append(n.get("name", ""))
            p = meshes[n["mesh"]]["primitives"][0]
            for key, a in p["attributes"].items():
                acc_tpl = data["accessors"][a]
                src_tpl[key] = acc_tpl
                out_attr.setdefault(key, array.array(COMP_FMT[acc_tpl["componentType"]]))
                out_attr[key].extend(acc_array(data, blob, a))
            iarr = acc_array(data, blob, p["indices"])
            out_idx.extend(x + vbase for x in iarr)
            vbase += acc_tpl["count"]
        attrs_out = {}
        for key, arr in out_attr.items():
            v = add_view(arr.tobytes(), 34962)
            attrs_out[key] = append_accessor(v, src_tpl[key], len(arr) // NCOMP[src_tpl[key]["type"]], key, arr)
        iv = add_view(out_idx.tobytes(), 34963)
        iacc = {"componentType": 5125, "count": len(out_idx), "type": "SCALAR",
                "min": [min(out_idx)], "max": [max(out_idx)]}
        v_idx = len(data["bufferViews"]) - 1
        iacc["bufferView"] = v_idx
        data["accessors"].append(iacc)
        mesh_idx = len(meshes)
        meshes.append({"name": "+".join(names), "primitives": [
            {"attributes": attrs_out, "indices": len(data["accessors"]) - 1,
             "material": mat}]})
        node_idx = len(nodes)
        nodes.append({"name": "+".join(names), "mesh": mesh_idx})
        new_children.append(node_idx)
        total_saved += len(ps) - 1

    group["children"] = new_children

    # --- prune dead data (nodes/meshes/accessors/views no longer referenced) ---
    scene = data.get("scenes", [{}])[0]
    reachable = []
    seen = set()
    def mark(i):
        if i in seen:
            return
        seen.add(i)
        reachable.append(i)
        for c in nodes[i].get("children", []):
            mark(c)
    for r in scene.get("nodes", []):
        mark(r)
    node_map = {i: k for k, i in enumerate(sorted(reachable))}
    kept_nodes = []
    for i in sorted(reachable):
        n = dict(nodes[i])
        if "children" in n:
            n["children"] = [node_map[c] for c in n["children"]]
        kept_nodes.append(n)

    # deep template maps taken BEFORE any remapping mutates shared dicts
    acc_src = {a: data["accessors"][a]["bufferView"] for a in range(len(data["accessors"]))}
    mesh_map = {}
    kept_meshes = []
    used_accs = set()
    for i in sorted(reachable):
        n = kept_nodes[node_map[i]]
        if "mesh" in n:
            old_m = nodes[i]["mesh"]
            if old_m not in mesh_map:
                mesh_map[old_m] = len(kept_meshes)
                km = json.loads(json.dumps(meshes[old_m]))
                kept_meshes.append(km)
                for pr in km.get("primitives", []):
                    used_accs |= set(pr.get("attributes", {}).values())
                    if "indices" in pr:
                        used_accs.add(pr["indices"])
            n["mesh"] = mesh_map[old_m]
    used_views = set()
    kept_accs = []
    acc_map = {}
    for a in sorted(used_accs):
        acc_map[a] = len(kept_accs)
        acc = dict(data["accessors"][a])
        used_views.add(acc["bufferView"])
        kept_accs.append(acc)
    img_views = {img["bufferView"] for img in data.get("images", []) if "bufferView" in img}
    used_views |= img_views
    old_blob = bytes(blob)
    view_map = {}
    kept_views = []
    new_blob = bytearray()
    for v in sorted(used_views):
        bv = data["bufferViews"][v]
        while len(new_blob) % 4:
            new_blob += b"\x00"
        payload = old_blob[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]]
        nb = dict(bv)
        nb["byteOffset"] = len(new_blob)
        nb["buffer"] = 0
        new_blob.extend(payload)
        view_map[v] = len(kept_views)
        kept_views.append(nb)
    blob[:] = new_blob
    for a_new, a_old in enumerate(sorted(used_accs)):
        kept_accs[a_new]["bufferView"] = view_map[acc_src[a_old]]
    for km in kept_meshes:
        for pr in km.get("primitives", []):
            pr["attributes"] = {k: acc_map[v] for k, v in pr.get("attributes", {}).items()}
            if "indices" in pr:
                pr["indices"] = acc_map[pr["indices"]]
    for img in data.get("images", []):
        if "bufferView" in img:
            img["bufferView"] = view_map[img["bufferView"]]
    for s in data.get("scenes", []):
        s["nodes"] = [node_map[r] for r in s["nodes"]]
    data["nodes"] = kept_nodes
    data["meshes"] = kept_meshes
    data["accessors"] = kept_accs
    data["bufferViews"] = kept_views

    while len(blob) % 4:
        blob += b"\x00"
    data["buffers"][0]["byteLength"] = len(blob)

    json_bytes = json.dumps(data, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4:
        json_bytes += b" "
    total = 12 + 8 + len(json_bytes) + 8 + len(blob)
    with open(outp, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(json_bytes), b"JSON"))
        f.write(json_bytes)
        f.write(struct.pack("<I4s", len(blob), b"BIN\0"))
        f.write(bytes(blob))
    print(f"{inp}: merged away {total_saved} nodes ({len(children)} -> {len(new_children)} children) -> {outp}")


if __name__ == "__main__":
    merge(sys.argv[1], sys.argv[2])
