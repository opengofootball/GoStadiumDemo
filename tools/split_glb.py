#!/usr/bin/env python3
"""Split a GLB into N self-contained parts (Workflow B).

Each output GLB keeps the original node hierarchy (root -> group -> leaves) so all
parts snap together at the shared origin, and re-embeds only the buffer views
(geometry + textures) that its meshes actually reference.

Usage: python3 tools/split_glb.py <input.glb> <out_dir> <num_parts>
"""
import struct
import json
import os
import sys
import math


CHUNK_JSON = 0x4E4F534A  # 'JSON'
CHUNK_BIN = 0x00494E42   # 'BIN\0'


def read_glb(path):
    with open(path, "rb") as f:
        magic, version, total = struct.unpack("<4sII", f.read(12))
        assert magic == b"glTF", magic
        clen, ctype = struct.unpack("<I4s", f.read(8))
        assert ctype == b"JSON", ctype
        data = json.loads(f.read(clen).decode("utf-8"))
        clen, ctype = struct.unpack("<I4s", f.read(8))
        assert ctype == b"BIN\0", ctype
        binchunk = f.read(clen)
    return data, binchunk


def accessor_bytes(data, acc_idx):
    acc = data["accessors"][acc_idx]
    return data["bufferViews"][acc["bufferView"]]["byteLength"]


def mesh_bytes(data, m_idx):
    """Total buffer-view bytes referenced by one mesh (deduped per bufferView)."""
    views = set()
    mesh = data["meshes"][m_idx]
    for p in mesh.get("primitives", []):
        attrs = p.get("attributes", {})
        for a_idx in attrs.values():
            views.add(data["accessors"][a_idx]["bufferView"])
        if "indices" in p:
            views.add(data["accessors"][p["indices"]]["bufferView"])
        for t_idx in p.get("targets", []):
            for a_idx in t_idx.values():
                views.add(data["accessors"][a_idx]["bufferView"])
    return sum(data["bufferViews"][v]["byteLength"] for v in views), views


def collect_materials(data, m_idx):
    mats = set()
    for p in data["meshes"][m_idx].get("primitives", []):
        if p.get("material") is not None:
            mats.add(p["material"])
    return mats


def collect_textures(data, mat_idx):
    """texture indices referenced by a material (baseColor, metallicRoughness, etc)."""
    texs = set()
    mat = data["materials"][mat_idx]
    pbr = mat.get("pbrMetallicRoughness", {})
    for key in ("baseColorTexture", "metallicRoughnessTexture"):
        if key in pbr:
            texs.add(pbr[key]["index"])
    for key in ("normalTexture", "occlusionTexture", "emissiveTexture"):
        if key in mat:
            texs.add(mat[key]["index"])
    return texs


def image_bytes(data, img_idx):
    src = data["images"][img_idx]
    if "bufferView" not in src:
        return 0, None
    bv = data["bufferViews"][src["bufferView"]]
    return bv["byteLength"], src["bufferView"]


def build_part(data, binchunk, mesh_indices, part_name, out_path):
    nodes = data["nodes"]
    meshes = data["meshes"]
    materials = data["materials"]
    textures = data["textures"]
    images = data["images"]
    accessors = data["accessors"]
    buffer_views = data["bufferViews"]

    # 1. Determine which nodes to keep (leaf nodes whose mesh is in this part) plus
    #    the ancestor chain from the scene root.
    kept_meshes = sorted(set(mesh_indices))
    mesh_set = set(kept_meshes)

    # map original node index -> kept node
    keep_nodes = {}

    # find the group node and root: walk scene
    scene = data["scenes"][0]
    root_idx = scene["nodes"][0]

    def ensure_node(orig):
        if orig in keep_nodes:
            return keep_nodes[orig]
        keep_nodes[orig] = dict(nodes[orig])  # shallow copy
        return len(keep_nodes) - 1

    # We rebuild children lists after deciding which leaves to keep.
    leaf_orig_indices = []
    for orig, n in enumerate(nodes):
        if n.get("mesh") is not None and n["mesh"] in mesh_set:
            leaf_orig_indices.append(orig)

    # Ensure ancestors of each kept leaf
    parent_of = {}
    for orig, n in enumerate(nodes):
        for c in n.get("children", []):
            parent_of[c] = orig

    for leaf in leaf_orig_indices:
        cur = leaf
        while cur is not None:
            ensure_node(cur)
            cur = parent_of.get(cur)

    # 2. Determine referenced materials / textures / images
    used_mats = set()
    used_texs = set()
    used_imgs = set()
    for m in kept_meshes:
        for mat in collect_materials(data, m):
            used_mats.add(mat)
            for t in collect_textures(data, mat):
                used_texs.add(t)
                img = textures[t]["source"]
                used_imgs.add(img)

    # 3. Determine referenced buffer views (geometry + images)
    used_views = set()
    for m in kept_meshes:
        _, views = mesh_bytes(data, m)
        used_views |= views
    for img in used_imgs:
        _, v = image_bytes(data, img)
        if v is not None:
            used_views.add(v)

    # 4. Pack buffer views into a fresh binary chunk (aligned), remapping offsets.
    view_order = sorted(used_views)
    new_views = []
    new_bin = bytearray()
    old_to_new_view = {}
    for old_v in view_order:
        bv = buffer_views[old_v]
        target = bv.get("target")
        align = 8 if target in (34962, 34963) else 4
        pad = (-len(new_bin)) % align
        if pad:
            new_bin.extend(b"\x00" * pad)
        new_off = len(new_bin)
        start = bv.get("byteOffset", 0)
        length = bv["byteLength"]
        new_bin.extend(binchunk[start:start + length])
        old_to_new_view[old_v] = len(new_views)
        nv = {"buffer": 0, "byteOffset": new_off, "byteLength": length}
        if target:
            nv["target"] = target
        new_views.append(nv)

    # pad binary chunk to 4 bytes
    while len(new_bin) % 4:
        new_bin.append(0)

    # 5. Remap accessors
    used_accs = set()
    for m in kept_meshes:
        for p in meshes[m].get("primitives", []):
            for a in p.get("attributes", {}).values():
                used_accs.add(a)
            if "indices" in p:
                used_accs.add(p["indices"])
    old_to_new_acc = {}
    new_accessors = []
    for old_a in sorted(used_accs):
        acc = dict(accessors[old_a])
        acc["bufferView"] = old_to_new_view[accessors[old_a]["bufferView"]]
        old_to_new_acc[old_a] = len(new_accessors)
        new_accessors.append(acc)

    # 6. Remap images -> textures -> materials (in dependency order)
    old_to_new_img = {}
    new_images = []
    for old_i in sorted(used_imgs):
        old_to_new_img[old_i] = len(new_images)
        img = dict(images[old_i])
        if "bufferView" in img:
            img["bufferView"] = old_to_new_view[img["bufferView"]]
        new_images.append(img)

    # Samplers referenced by the kept textures (remapped to a compact list)
    samplers_src = data.get("samplers", [])  # top-level glTF samplers array
    used_samplers = set()
    for old_t in used_texs:
        s = textures[old_t].get("sampler")
        if s is not None:
            used_samplers.add(s)

    old_to_new_sampler = {}
    new_samplers = []
    for old_s in sorted(used_samplers):
        old_to_new_sampler[old_s] = len(new_samplers)
        new_samplers.append(dict(samplers_src[old_s]))

    old_to_new_tex = {}
    new_textures = []
    for old_t in sorted(used_texs):
        old_to_new_tex[old_t] = len(new_textures)
        t = dict(textures[old_t])
        t["source"] = old_to_new_img[t["source"]]
        if t.get("sampler") is not None:
            t["sampler"] = old_to_new_sampler[t["sampler"]]
        new_textures.append(t)

    old_to_new_mat = {}
    new_materials = []
    for old_mat in sorted(used_mats):
        old_to_new_mat[old_mat] = len(new_materials)
        mat = json.loads(json.dumps(materials[old_mat]))
        pbr = mat.get("pbrMetallicRoughness", {})
        for key in ("baseColorTexture", "metallicRoughnessTexture"):
            if key in pbr:
                pbr[key]["index"] = old_to_new_tex[pbr[key]["index"]]
        for key in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            if key in mat:
                mat[key]["index"] = old_to_new_tex[mat[key]["index"]]
        new_materials.append(mat)

    # 7. Remap meshes (now that material remap exists)
    old_to_new_mesh = {}
    new_meshes = []
    for old_m in kept_meshes:
        m = json.loads(json.dumps(meshes[old_m]))  # deep copy
        for p in m.get("primitives", []):
            attrs = p.get("attributes", {})
            for k, a in attrs.items():
                attrs[k] = old_to_new_acc[a]
            if "indices" in p:
                p["indices"] = old_to_new_acc[p["indices"]]
            if p.get("material") is not None:
                p["material"] = old_to_new_mat[p["material"]]
        old_to_new_mesh[old_m] = len(new_meshes)
        new_meshes.append(m)

    # 8. Rebuild nodes. Children are derived from parent_of using ORIGINAL indices
    #    (exactly one parent per node), then remapped to new indices.
    ordered = sorted(keep_nodes.keys())
    orig_to_new = {orig: i for i, orig in enumerate(ordered)}

    kids_of = {orig: [] for orig in ordered}
    for orig in ordered:
        par = parent_of.get(orig)
        if par in keep_nodes and par != orig:
            kids_of[par].append(orig)

    new_nodes = []
    for orig in ordered:
        n = dict(keep_nodes[orig])
        kids = sorted(orig_to_new[c] for c in kids_of[orig])
        if kids:
            n["children"] = kids
        else:
            n.pop("children", None)
        if n.get("mesh") is not None and n["mesh"] in old_to_new_mesh:
            n["mesh"] = old_to_new_mesh[n["mesh"]]
        new_nodes.append(n)

    new_root = orig_to_new[root_idx]

    # 9. Assemble glTF JSON
    new_data = {
        "asset": {"version": "2.0", "generator": "split_glb"},
        "scene": 0,
        "scenes": [{"name": part_name, "nodes": [new_root]}],
        "nodes": new_nodes,
        "meshes": new_meshes,
        "materials": new_materials,
        "textures": new_textures,
        "images": new_images,
        "accessors": new_accessors,
        "bufferViews": new_views,
        "buffers": [{"byteLength": len(new_bin)}],
    }
    if new_samplers:
        new_data["samplers"] = new_samplers

    json_bytes = json.dumps(new_data, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4:
        json_bytes += b" "
    bin_bytes = bytes(new_bin)
    while len(bin_bytes) % 4:
        bin_bytes += b"\x00"

    total = 12 + 8 + len(json_bytes) + 8 + len(bin_bytes)
    with open(out_path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(json_bytes), b"JSON"))
        f.write(json_bytes)
        f.write(struct.pack("<I4s", len(bin_bytes), b"BIN\0"))
        f.write(bin_bytes)

    return os.path.getsize(out_path)


def main():
    inp, out_dir, nparts = sys.argv[1], sys.argv[2], int(sys.argv[3])
    data, binchunk = read_glb(inp)

    # Only split leaf nodes that have a mesh
    leaf_meshes = []
    for orig, n in enumerate(data["nodes"]):
        if n.get("mesh") is not None:
            leaf_meshes.append(n["mesh"])

    # Compute per-mesh size and bucket-pack into N parts by descending size
    sizes = {}
    for m in set(leaf_meshes):
        sizes[m] = mesh_bytes(data, m)[0]
    ordered = sorted(set(leaf_meshes), key=lambda m: sizes[m], reverse=True)

    buckets = [[] for _ in range(nparts)]
    loads = [0] * nparts
    for m in ordered:
        i = loads.index(min(loads))
        buckets[i].append(m)
        loads[i] += sizes[m]

    os.makedirs(out_dir, exist_ok=True)
    base = os.path.splitext(os.path.basename(inp))[0]
    print(f"Input: {inp}  total geometry ~{sum(sizes.values())/1e6:.1f} MB across {len(set(leaf_meshes))} meshes")
    for i, b in enumerate(buckets):
        part_name = f"{base}_part{i+1:02d}"
        out_path = os.path.join(out_dir, part_name + ".glb")
        sz = build_part(data, binchunk, b, part_name, out_path)
        print(f"  {part_name}.glb  {sz/1e6:.1f} MB  ({len(b)} meshes)")


if __name__ == "__main__":
    main()
