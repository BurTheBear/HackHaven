import bpy,os,json,math
from mathutils import Vector
O=os.path.dirname(os.path.abspath(__file__))
bpy.ops.wm.open_mainfile(filepath=O+'/Listener.blend')
s=bpy.context.scene;ob=next(o for o in s.objects if o.type=='MESH' and 'HOLLOW' in o.name);rig=next(o for o in s.objects if o.type=='ARMATURE')
bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
s.cycles.samples=1
normal=bpy.data.images.new('Listener_Normal_2K',width=2048,height=2048,alpha=False);normal.colorspace_settings.name='Non-Color'
for m in ob.data.materials:
 n=m.node_tree.nodes;im=n.new('ShaderNodeTexImage');im.image=normal;n.active=im
bpy.ops.object.bake(type='NORMAL')
normal.filepath_raw=O+'/Listener_Normal_2K.png';normal.file_format='PNG';normal.save();normal.pack()
for m in ob.data.materials:
 n=m.node_tree.nodes;l=m.node_tree.links;p=n.get('Principled BSDF');im=next(x for x in n if x.type=='TEX_IMAGE' and x.image==normal);nm=n.new('ShaderNodeNormalMap');l.new(im.outputs['Color'],nm.inputs['Color']);l.new(nm.outputs[0],p.inputs['Normal'])
for t in rig.animation_data.nla_tracks:t.mute=False
rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=O+'/Listener.glb',export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_nla_strips=True,export_skins=True)
# Smaller geometric option preserves the same skeleton, atlas, clips and silhouette.
bpy.context.view_layer.objects.active=ob
dec=ob.modifiers.new('Web LOD','DECIMATE');dec.ratio=.48
bpy.ops.export_scene.gltf(filepath=O+'/Listener_Web.glb',export_format='GLB',use_selection=True,export_apply=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_nla_strips=True,export_skins=True)
ob.modifiers.remove(dec)
for t in rig.animation_data.nla_tracks:t.mute=True
rig.animation_data.action=None
for p in rig.pose.bones:p.rotation_euler=(0,0,0);p.scale=(1,1,1);p.location=(0,0,0)
s.cycles.samples=32
bpy.ops.wm.save_as_mainfile(filepath=O+'/Listener.blend')
# Echo silhouette image. Presentation shader only, separate from GLB materials.
echo=bpy.data.materials.new('Echo preview red');echo.use_nodes=True;n=echo.node_tree.nodes;n.clear();l=echo.node_tree.links
out=n.new('ShaderNodeOutputMaterial');em=n.new('ShaderNodeEmission');em.inputs[0].default_value=(1,.025,.055,1)
layer=n.new('ShaderNodeLayerWeight');r=n.new('ShaderNodeValToRGB');r.color_ramp.elements[0].position=.12;r.color_ramp.elements[0].color=(.015,.015,.015,1);r.color_ramp.elements[1].position=.8;r.color_ramp.elements[1].color=(.85,.85,.85,1)
l.new(layer.outputs['Facing'],r.inputs[0]);l.new(r.outputs[0],em.inputs['Strength']);l.new(em.outputs[0],out.inputs[0])
for i in range(len(ob.data.materials)):ob.data.materials[i]=echo
for o in s.objects:
 if o.type=='LIGHT':o.hide_render=True
 if o.type=='MESH' and o!=ob:o.hide_render=True
s.world.color=(0,0,0);s.render.filepath=O+'/Listener_Echo.png';s.render.resolution_x=1000;s.render.resolution_y=1200;s.cycles.samples=16
bpy.ops.render.render(write_still=True)
print('FINALIZE_COMPLETE')
