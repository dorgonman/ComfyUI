import math
import os
import sys

import bpy
from mathutils import Vector


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


args = sys.argv[sys.argv.index("--") + 1 :]
source, output_dir = args[:2]
options = set(args[2:])
preserve_materials = "preserve" in options
transparent_background = "transparent" in options
cpu_render = "cpu" in options
os.makedirs(output_dir, exist_ok=True)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=source)

meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
minimum = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
maximum = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
center = (minimum + maximum) * 0.5
extent = maximum - minimum

if not preserve_materials:
    material = bpy.data.materials.new("ReviewSkin")
    material.diffuse_color = (0.58, 0.30, 0.22, 1.0)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.58, 0.30, 0.22, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.72
    for mesh in meshes:
        mesh.data.materials.clear()
        mesh.data.materials.append(material)

for mesh in meshes:
    for polygon in mesh.data.polygons:
        polygon.use_smooth = True

world = bpy.context.scene.world or bpy.data.worlds.new("World")
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.035, 0.035, 0.045, 1.0)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.32

for name, location, energy, size in (
    ("Key", center + Vector((-2.5, -3.0, 3.0)), 900.0, 4.0),
    ("Fill", center + Vector((3.0, -1.5, 1.0)), 500.0, 3.0),
    ("Rim", center + Vector((0.0, 3.0, 2.5)), 700.0, 3.0),
):
    light_data = bpy.data.lights.new(name=name, type="AREA")
    light_data.energy = energy
    light_data.shape = "DISK"
    light_data.size = size
    light = bpy.data.objects.new(name, light_data)
    bpy.context.collection.objects.link(light)
    light.location = location
    look_at(light, center)

camera_data = bpy.data.cameras.new("ReviewCamera")
camera_data.type = "ORTHO"
camera_data.ortho_scale = max(extent) * 1.22
camera = bpy.data.objects.new("ReviewCamera", camera_data)
bpy.context.collection.objects.link(camera)
bpy.context.scene.camera = camera

scene = bpy.context.scene
if cpu_render:
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.cycles.use_denoising = True
else:
    scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 640
scene.render.resolution_y = 640
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = transparent_background
scene.render.image_settings.color_mode = "RGBA"

distance = max(extent) * 2.5
views = {
    "front": center + Vector((0.0, -distance, 0.0)),
    "back": center + Vector((0.0, distance, 0.0)),
    "right": center + Vector((distance, 0.0, 0.0)),
    "left": center + Vector((-distance, 0.0, 0.0)),
}
for name, location in views.items():
    camera.location = location
    look_at(camera, center)
    scene.render.filepath = os.path.join(output_dir, f"{name}.png")
    bpy.ops.render.render(write_still=True)

print(f"Rendered {len(views)} views to {output_dir}")
