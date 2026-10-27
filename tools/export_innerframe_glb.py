"""Export innerframe run cycle GLB from Blender to Godot with canonical MechaRig bone mapping.

This tool:
1. Connects to Blender or processes a GLB export from scratch/innerframe_animation_handmade.blend.
2. Ensures the 24 canonical MechaRig bone names are mapped onto the skin joints.
3. Transfers the Armature object-level Z-bob animation into Bone_Hip translation.
4. Normalizes the animation action name to 'run' (matching MechaRig.CLIP_RUN).
5. Writes scenes/mecha/animations/innerframe_run_cycle_clean.glb for Godot 4.6.2 consumption.
"""

import struct
import json
import os
import sys

BONE_MAP = {
    'pelvis': 'Bone_Hip',
    'abs': 'Bone_Spine1',
    'Bone': 'Bone_Spine2',
    'Bone.001': 'Bone_Torso',
    'Bone.032': 'Bone_Neck',
    'Bone.033': 'Bone_Head',
    'Bone.002.R': 'Bone_Collar_L',
    'Bone.019.R': 'Bone_UpperArm_L',
    'Bone.020.R': 'Bone_LowerArm_L',
    'Bone.022.R': 'Bone_Hand_L',
    'Bone.002.L': 'Bone_Collar_R',
    'Bone.019.L': 'Bone_UpperArm_R',
    'Bone.020.L': 'Bone_LowerArm_R',
    'Bone.022.L': 'Bone_Hand_R',
    'Bone.006.R': 'Bone_Thigh_L',
    'Bone.007.R': 'Bone_Shin_L',
    'Bone.014.R': 'Bone_Ankle_L',
    'Bone.016.R': 'Bone_Foot_L',
    'Bone.015.R': 'Bone_Toe_L',
    'Bone.006.L': 'Bone_Thigh_R',
    'Bone.007.L': 'Bone_Shin_R',
    'Bone.014.L': 'Bone_Ankle_R',
    'Bone.016.L': 'Bone_Foot_R',
    'Bone.015.L': 'Bone_Toe_R',
}

def clean_glb(input_path: str, output_path: str) -> bool:
    if not os.path.exists(input_path):
        print(f"Error: input file {input_path} not found.")
        return False

    with open(input_path, 'rb') as f:
        raw = f.read()

    json_len = struct.unpack('<I', raw[12:16])[0]
    g = json.loads(raw[20:20+json_len].decode('utf-8'))
    bin_chunk = bytearray(raw[20+json_len+8:]) # skip BIN header

    def read_acc_vec3(acc_idx):
        acc = g['accessors'][acc_idx]
        bv = g['bufferViews'][acc['bufferView']]
        st = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
        cnt = acc['count']
        return [struct.unpack_from('<3f', bin_chunk, st + i*12) for i in range(cnt)]

    def append_acc_vec3(vals):
        pad = (4 - (len(bin_chunk) % 4)) % 4
        bin_chunk.extend(b'\\x00' * pad)
        st = len(bin_chunk)
        for v in vals:
            bin_chunk.extend(struct.pack('<3f', *v))
        bv_idx = len(g['bufferViews'])
        g['bufferViews'].append({
            'buffer': 0,
            'byteOffset': st,
            'byteLength': len(vals) * 12
        })
        acc_idx = len(g['accessors'])
        mins = [min(v[i] for v in vals) for i in range(3)]
        maxs = [max(v[i] for v in vals) for i in range(3)]
        g['accessors'].append({
            'bufferView': bv_idx,
            'componentType': 5126,
            'count': len(vals),
            'type': 'VEC3',
            'min': mins,
            'max': maxs
        })
        return acc_idx

    # Find Armature node and pelvis node
    arm_node_idx = None
    pelvis_node_idx = None
    for i, n in enumerate(g.get('nodes', [])):
        if n.get('name') == 'Armature':
            arm_node_idx = i
        elif n.get('name') == 'pelvis' and 'children' in n:
            pelvis_node_idx = i

    # Collect skin joints
    joint_indices = set()
    for s in g.get('skins', []):
        joint_indices.update(s.get('joints', []))

    # Rename joint nodes
    renamed = 0
    for idx in joint_indices:
        n = g['nodes'][idx]
        old_name = n.get('name')
        if old_name in BONE_MAP:
            n['name'] = BONE_MAP[old_name]
            renamed += 1
    print(f"Renamed {renamed} joint nodes to canonical MechaRig names.")

    # Rename animation to run and transfer hip bob
    for anim in g.get('animations', []):
        if anim.get('name') in ('RunCycle', 'run'):
            anim['name'] = 'run'
        arm_trans_sam_idx = None
        for ch in anim.get('channels', []):
            if ch['target']['node'] == arm_node_idx and ch['target']['path'] == 'translation':
                arm_trans_sam_idx = ch['sampler']
                break
        if arm_trans_sam_idx is not None and pelvis_node_idx is not None:
            sam = anim['samplers'][arm_trans_sam_idx]
            arm_vals = read_acc_vec3(sam['output'])
            pelvis_rest = g['nodes'][pelvis_node_idx].get('translation', [0, 0, 0])
            combined_vals = [
                (pelvis_rest[0] + av[0], pelvis_rest[1] + av[1], pelvis_rest[2] + av[2])
                for av in arm_vals
            ]
            new_acc = append_acc_vec3(combined_vals)
            new_sam_idx = len(anim['samplers'])
            anim['samplers'].append({
                'input': sam['input'],
                'interpolation': sam.get('interpolation', 'LINEAR'),
                'output': new_acc
            })
            found_pelvis_ch = False
            for ch in anim['channels']:
                if ch['target']['node'] == pelvis_node_idx and ch['target']['path'] == 'translation':
                    ch['sampler'] = new_sam_idx
                    found_pelvis_ch = True
                    break
            if not found_pelvis_ch:
                anim['channels'].append({
                    'sampler': new_sam_idx,
                    'target': {'node': pelvis_node_idx, 'path': 'translation'}
                })
            zero_vals = [(0.0, 0.0, 0.0)] * len(arm_vals)
            zero_acc = append_acc_vec3(zero_vals)
            sam['output'] = zero_acc
            print("Successfully transferred Armature translation bob into Bone_Hip.")

    # Update buffer byteLength
    g['buffers'][0]['byteLength'] = len(bin_chunk)

    new_json_bytes = json.dumps(g).encode('utf-8')
    pad = (4 - (len(new_json_bytes) % 4)) % 4
    new_json_bytes += b' ' * pad

    bin_pad = (4 - (len(bin_chunk) % 4)) % 4
    bin_chunk.extend(b'\\x00' * bin_pad)

    new_total_len = 12 + 8 + len(new_json_bytes) + 8 + len(bin_chunk)
    header = struct.pack('<4sII', b'glTF', 2, new_total_len)
    json_chunk_hdr = struct.pack('<II', len(new_json_bytes), 0x4E4F534A)
    bin_chunk_hdr = struct.pack('<II', len(bin_chunk), 0x004E4942)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'wb') as f:
        f.write(header)
        f.write(json_chunk_hdr)
        f.write(new_json_bytes)
        f.write(bin_chunk_hdr)
        f.write(bin_chunk)

    print(f"Export cleaned GLB written to {output_path} ({os.path.getsize(output_path)} bytes).")
    return True

if __name__ == '__main__':
    src = sys.argv[1] if len(sys.argv) > 1 else 'scratch/test_export.glb'
    dst = sys.argv[2] if len(sys.argv) > 2 else 'scenes/mecha/animations/innerframe_run_cycle_clean.glb'
    clean_glb(src, dst)
