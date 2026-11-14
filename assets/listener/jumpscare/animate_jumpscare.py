import bpy, math, os, json, random
from mathutils import Vector,Quaternion
from math import sin,cos,pi
O=os.path.dirname(os.path.abspath(__file__))
SRC=os.path.abspath(os.path.join(O,'..','Listener.blend'))
bpy.ops.wm.open_mainfile(filepath=SRC)
s=bpy.context.scene
rig=next(o for o in s.objects if o.type=='ARMATURE');mesh=next(o for o in s.objects if o.type=='MESH' and 'HOLLOW' in o.name)
for o in list(s.objects):
 if o not in (rig,mesh):bpy.data.objects.remove(o,do_unlink=True)
rig.animation_data_clear();mesh.animation_data_clear()
for p in rig.pose.bones:
 p.rotation_mode='XYZ';p.rotation_euler=(0,0,0);p.location=(0,0,0);p.scale=(1,1,1)
rig.scale=(.72,)*3;rig.name='Listener_Jumpscare_Rig';mesh.name='Listener_Jumpscare_Mesh'
# Facial shape keys follow the existing sculpture and the head bone.
basis=mesh.shape_key_add(name='Basis');scream=mesh.shape_key_add(name='Scream');flare=mesh.shape_key_add(name='Hearing_Crown_Flare')
gid=mesh.vertex_groups['head'].index
for i,v in enumerate(mesh.data.vertices):
 if not any(g.group==gid and g.weight>.5 for g in v.groups):continue
 x,y,z=v.co
 if abs(x)<.43 and y<.035 and 2.12<z<3.13:
  radial=math.sqrt((x/.4)**2+((z-2.59)/.52)**2)
  inner=max(0,1-radial/1.3)
  scream.data[i].co.x=x*(1.0+.4*inner)
  scream.data[i].co.z=2.59+(z-2.59)*(1.12+.55*inner)
  scream.data[i].co.y=y-.055*inner
 if abs(x)>.31 and z>2.4:
  w=min(1,(abs(x)-.31)/.28)
  flare.data[i].co.x=x+math.copysign(.2*w,x)
  flare.data[i].co.y=y-.11*w
  flare.data[i].co.z=z+.06*w
s.frame_start=1;s.frame_end=96;s.render.fps=24
# Pose beats: no camera cut conceals the actual approach. A still hold precedes
# a delayed eight-frame attack; different hands arrive on different frames.
beats=[
 # frame, forward, crouch, head tilt, head turn, neck bend, arm L, arm R, scream, flare
 (1,0,0,-.03,.02,.035,0,0,0,0),
 (20,.01,0,.015,-.02,.015,.01,-.01,0,.04),
 (31,.025,-.015,-.08,.13,.04,0,0,0,.12),
 (38,.035,-.035,-.42,.28,.10,.025,-.02,.08,.25),
 (44,-.10,-.14,-.35,.24,.23,-.12,-.15,.03,.16),
 (47,.10,-.12,-.17,.09,.20,-.32,-.22,.12,.2),
 (49,.65,-.10,-.08,.03,.10,-.70,-.50,.42,.65),
 (51,2.0,-.04,.08,-.04,-.06,-1.30,-1.06,.85,1),
 (54,4.8,.02,.15,.03,-.15,-1.80,-1.65,1,1),
 (57,5.7,.04,-.13,-.08,-.21,-1.95,-1.82,1,.9),
 (60,5.50,.015,.06,.06,-.15,-1.85,-1.95,.85,1),
 (64,5.65,.025,-.09,-.03,-.18,-1.91,-1.80,1,.93),
 (69,5.56,.03,.08,.05,-.18,-1.85,-1.93,.92,1),
 (74,5.66,.025,-.05,-.04,-.18,-1.92,-1.87,1,.95),
 (78,5.67,.025,-.04,-.04,-.18,-1.92,-1.87,1,.95),
 (96,5.67,.025,-.04,-.04,-.18,-1.92,-1.87,1,.95),
]
rig.animation_data_create();rig.animation_data.action=bpy.data.actions.new('Jumpscare_Caught')
for f,forward,z,tilt,turn,neck,al,ar,sc,fl in beats:
 p=rig.pose.bones
 for b in p:b.rotation_euler=(0,0,0);b.location=(0,0,0);b.scale=(1,1,1)
 # Root local Y is vertical in the bone frame: move root with a world-space
 # offset converted through its rest basis so forward means Blender -Y.
 world_offset=Vector((.035*sin(f*.5) if f>51 else 0,-forward,z))
 p['root'].location=rig.data.bones['root'].matrix_local.to_3x3().inverted()@world_offset
 p['chest'].rotation_euler=(.035 if f<44 else -.10,0,.025*sin(f*.15))
 p['neck'].rotation_euler[0]=neck
 p['head'].rotation_euler=(0,tilt,turn)
 p['upper_arm.L'].rotation_euler=(0,0,0)
 p['upper_arm.R'].rotation_euler=(0,0,0)
 p['forearm.L'].rotation_euler[0]=-.35 if f>49 else .04
 p['forearm.R'].rotation_euler[0]=-.44 if f>51 else .02
 p['hand.L'].rotation_euler[2]=-.2 if f>49 else .03
 p['hand.R'].rotation_euler[2]=.23 if f>51 else 0
 if f>=47:
  p['thigh.L'].rotation_euler[0]=-.22;p['shin.L'].rotation_euler[0]=.28;p['thigh.R'].rotation_euler[0]=.16
 p['chest'].scale=(1+.025*sc,1+.07*sc,1+.015*sc)
 # Solve each reaching chain in armature space. This keeps the claws beside
 # the face instead of letting local-axis rotations cross the wrists.
 bpy.context.view_layer.update()
 for side,sign in [('L',-1),('R',1)]:
  reach=max(0,min(1,(f-(47 if side=='L' else 49))/7))
  for name,direction in [('upper_arm.'+side,(sign*(.23 if side=='L' else .30),-.55,.10 if side=='L' else -.02)),('forearm.'+side,(sign*.08,-.66,.08 if side=='L' else .01)),('hand.'+side,(sign*-.035,-.6,-.03))]:
   b=p[name];rest=rig.data.bones[name]
   desired=(rest.tail_local-rest.head_local).normalized().rotation_difference(Vector(direction).normalized()) @ rest.matrix_local.to_quaternion()
   current=b.matrix.to_quaternion();q=current.slerp(desired,reach)
   matrix=q.to_matrix().to_4x4();matrix.translation=b.head
   b.matrix=matrix
   bpy.context.view_layer.update()
 for b in p:
  b.keyframe_insert('location',frame=f,group=b.name);b.keyframe_insert('rotation_euler',frame=f,group=b.name);b.keyframe_insert('scale',frame=f,group=b.name)
 scream.value=sc;scream.keyframe_insert('value',frame=f);flare.value=fl;flare.keyframe_insert('value',frame=f)
# Use linear attack interpolation to avoid Bezier slowing the hit. Bézier
# anticipation retains the organic drift before it.
def curves(action):
 for layer in action.layers:
  for strip in layer.strips:
   for bag in strip.channelbags:
    for curve in bag.fcurves:yield curve
for action in [rig.animation_data.action,mesh.data.shape_keys.animation_data.action]:
 for curve in curves(action):
  for k in curve.keyframe_points:
   if 47<=k.co.x<=60:k.interpolation='LINEAR'
   else:k.handle_left_type='AUTO_CLAMPED';k.handle_right_type='AUTO_CLAMPED'
# Export synchronized rig and morph tracks with one shared NLA name.
for target in [rig,mesh.data.shape_keys]:
 action=target.animation_data.action
 track=target.animation_data.nla_tracks.new();track.name='Jumpscare_Caught';track.strips.new('Jumpscare_Caught',1,action)
 target.animation_data.action=None
bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=O+'/Listener_Jumpscare.glb',export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_nla_strips=True,export_skins=True,export_morph=True,export_frame_range=True)
# Set and dressing: a real corridor with beams and foreground occlusion.
def mat(name,color,rough=.8):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough;return m
stone=mat('Wet charcoal stone',(.018,.028,.032));wood=mat('Blackened timber',(.028,.019,.012));dark=mat('Absolute darkness',(.001,.001,.001))
def box(name,loc,scale,material,bevel=.03):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(material)
 if bevel:
  mod=o.modifiers.new('Worn edges','BEVEL');mod.width=bevel;mod.segments=2;o.modifiers.new('Weighted corners','WEIGHTED_NORMAL')
 return o
box('Wet mine floor',(0,1,-.06),(8,20,.12),stone)
box('Left rock wall',(-2.1,1,1.6),(.5,20,3.4),stone,.12);box('Right rock wall',(2.1,1,1.6),(.5,20,3.4),stone,.12)
box('Low ceiling',(0,1,3.2),(4.5,20,.3),stone)
for y in [1.4,4.2,7]:
 for x in [-1.67,1.67]:box('Timber upright',(x,y,1.48),(.18,.18,3),wood)
 box('Crossbeam',(0,y,2.92),(3.5,.2,.22),wood)
# Chunks disappear into black. The character is framed by purposeful negative space.
random.seed(81)
for i in range(32):
 x=random.choice([-1,1])*random.uniform(1.35,1.8);y=random.uniform(-3,8)
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=random.uniform(.08,.27),location=(x,y,.05));o=bpy.context.object;o.scale=(1.5,1,.7);o.data.materials.append(stone)
# Camera at human eye level, entirely continuous until the blackout.
camdata=bpy.data.cameras.new('Player POV');cam=bpy.data.objects.new('Player POV',camdata);s.collection.objects.link(cam);s.camera=cam
camdata.lens=35;camdata.sensor_width=36;camdata.clip_start=.04;camdata.clip_end=100
base=Vector((0,-6,1.63))
def aim(point):cam.rotation_euler=(Vector(point)-cam.location).to_track_quat('-Z','Y').to_euler()
for f in [1,20,31,38,44,47,49,51,54,56,58,60,62,64,67,70,74,78,96]:
 cam.location=base.copy()
 recoil=max(0,min(1,(f-51)/6))
 cam.location.y-=.19*recoil
 if 54<=f<=74:
  cam.location.x+=.025*sin(f*2.1);cam.location.z+=.015*cos(f*1.7)
 attack=max(0,min(1,(f-49)/7))
 target=Vector((0,-.5,1.78)).lerp(Vector((0,-4.15,2.1)),attack)
 aim(target)
 if 54<=f<=74:
  cam.rotation_euler.z+=.018*sin(f*1.4)
 cam.keyframe_insert('location',frame=f);cam.keyframe_insert('rotation_euler',frame=f)
 camdata.lens=35 if f<49 else (32 if f<54 else 29);camdata.keyframe_insert('lens',frame=f)
# Pulsing red reveal on the creature only, leaving its material intact.
for m in mesh.data.materials:
 nt=m.node_tree;n=nt.nodes;l=nt.links;p=n.get('Principled BSDF')
 noise=n.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=85;noise.inputs['Detail'].default_value=3
 bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.24;bump.inputs['Distance'].default_value=.022;l.new(noise.outputs['Fac'],bump.inputs['Height']);l.new(bump.outputs['Normal'],p.inputs['Normal'])
 layer=n.new('ShaderNodeLayerWeight');rim=n.new('ShaderNodeMath');rim.operation='MULTIPLY';l.new(layer.outputs['Facing'],rim.inputs[0])
 p.inputs['Emission Color'].default_value=(1,.012,.03,1);l.new(rim.outputs[0],p.inputs['Emission Strength'])
 for f,val in [(1,.015),(15,.025),(29,.1),(38,.14),(44,.02),(48,.07),(51,.08),(54,.16),(58,.10),(72,.075),(78,.075),(79,0),(96,0)]:
  rim.inputs[1].default_value=val;rim.inputs[1].keyframe_insert('default_value',frame=f)
def area(name,loc,color,size):
 d=bpy.data.lights.new(name,'AREA');d.color=color;d.shape='DISK';d.size=size;o=bpy.data.objects.new(name,d);s.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,-1,1.8))-o.location).to_track_quat('-Z','Y').to_euler();return o
key=area('Cold player bounce',(-.4,-4.9,2.3),(.38,.65,.7),2.3)
rimlight=area('Distant red mine glow',(0,1.8,2.2),(1,.035,.045),2)
face=area('Attack reveal',(-1.2,-5.4,2.5),(1,.10,.08),1.0)
for f,power in [(1,8),(29,12),(38,22),(44,3),(49,6),(52,30),(54,95),(59,60),(78,60),(79,0),(96,0)]:
 key.data.energy=power*.55;key.data.keyframe_insert('energy',frame=f)
 rimlight.data.energy=power*1.8;rimlight.data.keyframe_insert('energy',frame=f)
 face.data.energy=power*.55 if f>=52 else 0;face.data.keyframe_insert('energy',frame=f)
# Hide geometry after the hit. A black frame is an authored edit, not a flash.
for o in list(s.objects):
 if o.type=='MESH':
  o.hide_render=False;o.keyframe_insert('hide_render',frame=78);o.hide_render=True;o.keyframe_insert('hide_render',frame=79)
s.world.use_nodes=True;bg=s.world.node_tree.nodes.get('Background');bg.inputs[0].default_value=(0,0,0,1);bg.inputs[1].default_value=0
s.render.engine='CYCLES';s.cycles.samples=12;s.cycles.use_denoising=True
s.render.resolution_x=1280;s.render.resolution_y=720;s.render.resolution_percentage=100
s.render.image_settings.file_format='PNG';s.render.film_transparent=False
s.view_settings.view_transform='AgX';s.view_settings.exposure=-1.0
s.render.use_motion_blur=True;s.render.motion_blur_shutter=.25
prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='METAL';prefs.get_devices()
for device in prefs.devices:device.use=device.type=='METAL'
s.cycles.device='GPU'
# Timeline provides clearly named edit beats.
for f,label in [(1,'LISTEN • no attack yet'),(31,'IT HEARS YOU'),(44,'COIL'),(49,'LUNGE'),(57,'CONTACT'),(79,'BLACKOUT')]:s.timeline_markers.new(label,frame=f)
s.frame_set(38)
for screen in bpy.data.screens:
 for a in screen.areas:
  if a.type=='VIEW_3D':a.spaces.active.region_3d.view_perspective='CAMERA'
bpy.ops.wm.save_as_mainfile(filepath=O+'/Listener_Jumpscare.blend')
for f in [38,57]:
 s.frame_set(f);s.render.filepath=O+'/check_%03d.png'%f;bpy.ops.render.render(write_still=True)
print('JUMPSCARE_BUILT')
