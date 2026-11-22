import bpy

def process_hand(input_path, output_path, hand_name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=input_path)
    
    scene = bpy.context.scene
    
    # Keep only Armature and hand mesh
    for obj in list(scene.objects):
        if obj.type == "ARMATURE":
            obj.name = f"{hand_name}_Rig"
            continue
        if obj.type == "MESH" and "hand" in obj.name.lower():
            obj.name = f"{hand_name}_Model"
            continue
        # Remove extra helper objects
        bpy.data.objects.remove(obj, do_unlink=True)
        
    mesh_obj = [o for o in scene.objects if o.type == "MESH"][0]
    arm_obj = [o for o in scene.objects if o.type == "ARMATURE"][0]
    
    # Setup skin material
    skin_mat = bpy.data.materials.new(name="PianistSkin")
    bsdf = skin_mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.96, 0.89, 0.84, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.38
        
    mesh_obj.data.materials.clear()
    mesh_obj.data.materials.append(skin_mat)
    
    # Export clean GLB
    bpy.ops.object.select_all(action="DESELECT")
    arm_obj.select_set(True)
    mesh_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLB",
        export_skins=True,
        export_materials="EXPORT",
        export_normals=True
    )
    print(f"Exported {output_path} successfully!")

process_hand("scratch/wonderland_l_hand.glb", "assets/hands/hand_3d_left.glb", "Hand_Left")
process_hand("scratch/wonderland_r_hand.glb", "assets/hands/hand_3d_right.glb", "Hand_Right")
