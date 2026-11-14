import bpy, math, random, json, os
from mathutils import Vector
from math import sin,cos,pi
random.seed(72)
OUT=os.path.dirname(os.path.abspath(__file__))
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for d in list(bpy.data.materials): bpy.data.materials.remove(d)
parts=[]

def material(name,low,high,rough=.6,scale=22):
 m=bpy.data.materials.new(name); m.use_nodes=True
 n=m.node_tree.nodes; l=m.node_tree.links; p=n.get('Principled BSDF')
 p.inputs['Roughness'].default_value=rough
 tex=n.new('ShaderNodeTexNoise'); tex.inputs['Scale'].default_value=scale*.18; tex.inputs['Detail'].default_value=4; tex.inputs['Roughness'].default_value=.75
 coord=n.new('ShaderNodeTexCoord'); l.new(coord.outputs['Generated'],tex.inputs['Vector'])
 ramp=n.new('ShaderNodeValToRGB'); ramp.color_ramp.elements[0].position=.2; ramp.color_ramp.elements[0].color=(*low,1); ramp.color_ramp.elements[1].position=.82; ramp.color_ramp.elements[1].color=(*high,1)
 l.new(tex.outputs['Fac'],ramp.inputs[0]); l.new(ramp.outputs[0],p.inputs['Base Color'])
 bump=n.new('ShaderNodeBump'); bump.inputs['Strength'].default_value=.22; bump.inputs['Distance'].default_value=.018
 fine=n.new('ShaderNodeTexNoise'); fine.inputs['Scale'].default_value=135; fine.inputs['Detail'].default_value=3; l.new(coord.outputs['Generated'],fine.inputs['Vector']); l.new(fine.outputs['Fac'],bump.inputs['Height']); l.new(bump.outputs[0],p.inputs['Normal'])
 return m
skin=material('01 • Basalt hide',(.026,.032,.036),(.16,.18,.16),.62,36)
bone=material('02 • Weathered cartilage',(.055,.044,.028),(.29,.245,.16),.49,32)
flesh=material('03 • Acoustic membrane',(.035,.004,.012),(.26,.028,.045),.4,48)
black=material('04 • Throat / keratin',(.003,.004,.006),(.025,.018,.024),.33,27)
tooth=material('05 • Worn ivory',(.24,.18,.11),(.68,.57,.36),.38,55)
scar=material('06 • Old sinew',(.09,.026,.022),(.29,.105,.065),.55,41)

def objmesh(name,verts,faces,mat,bn):
 me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update()
 ob=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(ob); ob.data.materials.append(mat)
 for p in me.polygons:p.use_smooth=True
 vg=ob.vertex_groups.new(name=bn); vg.add(list(range(len(verts))),1,'REPLACE'); parts.append(ob)
 return ob

def tube(name,pts,radii,mat,bn,sides=9):
 pts=[Vector(p) for p in pts]; vs=[]; fs=[]
 for i,p in enumerate(pts):
  t=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized(); ref=Vector((0,1,0))
  if abs(t.dot(ref))>.94:ref=Vector((1,0,0))
  u=t.cross(ref).normalized(); v=t.cross(u).normalized()
  rr=radii[i] if isinstance(radii,(list,tuple)) else radii
  if isinstance(rr,(tuple,list)):a,b=rr
  else:a=b=rr
  for j in range(sides):
   q=p+u*cos(2*pi*j/sides)*a+v*sin(2*pi*j/sides)*b; vs.append(q)
 for i in range(len(pts)-1):
  for j in range(sides):
   k=i*sides+j; nj=i*sides+(j+1)%sides
   fs.append((k,nj,nj+sides,k+sides))
 fs.append(tuple(reversed(range(sides)))); fs.append(tuple((len(pts)-1)*sides+j for j in range(sides)))
 return objmesh(name,vs,fs,mat,bn)

def smoothpath(ctrl,steps=5):
 # Catmull-Rom, for intentionally shaped tendons and bone arcs.
 out=[]; arr=[Vector(ctrl[0])]+[Vector(p) for p in ctrl]+[Vector(ctrl[-1])]
 for i in range(1,len(arr)-2):
  a,b,c,d=arr[i-1:i+3]
  for j in range(steps):
   t=j/steps; out.append(tuple(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)))
 out.append(tuple(arr[-2])); return out

def arc(name,ctrl,r0,r1,mat,bn,sides=8,steps=5):
 pts=smoothpath(ctrl,steps); rr=[r0+(r1-r0)*(i/(len(pts)-1)) for i in range(len(pts))]
 return tube(name,pts,rr,mat,bn,sides)

def ell(name,loc,scale,mat,bn,seg=16,rings=10):
 vs=[];fs=[]
 for i in range(rings+1):
  a=pi*i/rings
  for j in range(seg):
   b=2*pi*j/seg
   # subtle skin irregularity; no perfectly spherical primitive finish
   w=1+.025*sin(j*3+i*2)
   vs.append((loc[0]+scale[0]*sin(a)*cos(b)*w,loc[1]+scale[1]*sin(a)*sin(b)*w,loc[2]+scale[2]*cos(a)))
 for i in range(rings):
  for j in range(seg):
   a=i*seg+j;b=i*seg+(j+1)%seg;fs.append((a,b,b+seg,a+seg))
 return objmesh(name,vs,fs,mat,bn)

# Narrow pelvis and continuous, forward-curved torso.
zs=[1.15,1.23,1.37,1.5,1.65,1.8,1.94,2.05,2.12]
width=[.16,.25,.22,.205,.27,.36,.4,.31,.14]
depth=[.13,.18,.15,.13,.17,.205,.21,.17,.11]
verts=[]; faces=[]
for i,z in enumerate(zs):
 cy=.09-.11*(i/(len(zs)-1))
 for j in range(32):
  a=2*pi*j/32;noise=1+.035*sin(5*a+i*.9)
  verts.append((width[i]*cos(a)*noise,cy+depth[i]*sin(a)*noise,z))
for i in range(len(zs)-1):
 for j in range(32):
  a=i*32+j;b=i*32+(j+1)%32;faces.append((a,b,b+32,a+32))
faces.extend([tuple(reversed(range(32))),tuple((len(zs)-1)*32+j for j in range(32))])
body=objmesh('Continuous flayed torso',verts,faces,skin,'chest')
# Blend torso across the pelvis and chest, for a breathing rig.
body.vertex_groups.clear(); gp=body.vertex_groups.new(name='pelvis');gc=body.vertex_groups.new(name='chest')
for i,v in enumerate(body.data.vertices):
 w=max(0,min(1,(v.co.z-1.25)/.55));gp.add([i],1-w,'REPLACE');gc.add([i],w,'REPLACE')

# Exposed sternum, floating ribs, and their recessed red membranes.
arc('Sternum keel',[(0,-.14,1.46),(0,-.24,1.72),(0,-.25,1.99)],.047,.06,bone,'chest',10)
for s in [-1,1]:
 for i in range(7):
  z=1.48+i*.077; w=.22+.145*sin((i+1)/8*pi*.85)
  ctrl=[(s*.03,-.19,z),(s*w*.6,-.245,z+.037),(s*w,-.08,z+.09),(s*w*.75,.15,z+.12)]
  arc('Costal arch %s %02d'%(s,i),ctrl,.035,.017,bone,'chest',9)
  arc('Intercostal tissue',[(s*.04,-.167,z+.034),(s*w*.6,-.211,z+.065),(s*(w-.03),-.055,z+.115)],.024,.012,flesh,'chest',7)
 arc('Clavicle',[(s*.015,-.18,2.0),(s*.2,-.2,2.08),(s*.4,-.035,2.03)],.048,.063,bone,'chest',10)
 arc('Iliac crest',[(s*.035,-.055,1.28),(s*.22,-.07,1.33),(s*.29,.1,1.21)],.04,.025,bone,'pelvis',10)
 arc('Abdominal cord',[(s*.17,-.10,1.22),(s*.12,-.145,1.4),(s*.19,-.15,1.58)],.025,.017,scar,'chest')
# Spinal vertebrae with backward hooks.
for i in range(13):
 z=1.25+i*.072; y=.22 if z>1.65 else .2
 ell('Dorsal vertebra %02d'%i,(0,y,z),(.075,.067,.045),bone,'chest' if z>1.45 else 'pelvis',12,6)
 if i%2==0:arc('Spinous hook',[(0,y,z),(0,y+.14,z+.025),(0,y+.17,z+.11)],.045,.002,bone,'chest',7)
# Taut bent neck with exposed tendons, carrying no eyes.
arc('Swan neck',[(0,.0,2.03),(0,.04,2.18),(0,-.02,2.36),(0,-.11,2.47)],.115,.14,skin,'neck',16,6)
for s in [-1,1]:
 arc('Neck tendon',[(s*.16,-.11,2.0),(s*.1,-.105,2.2),(s*.13,-.2,2.4)],.025,.018,scar,'neck')

# Head: deeply cupped, eyeless acoustic funnel. Front is -Y.
# Ring profile turns inward and backwards to a dark throat.
N=64
profiles=[(.33,.45,-.13),(.40,.51,-.33),(.355,.46,-.43),(.28,.36,-.34),(.19,.25,-.17),(.12,.17,-.025)]
vs=[];fs=[]
for k,(rx,rz,y) in enumerate(profiles):
 for j in range(N):
  a=2*pi*j/N; scallop=1+.045*sin(7*a+.4)+.025*sin(13*a)
  vs.append((rx*cos(a)*scallop,y+.025*cos(4*a),2.59+rz*sin(a)*scallop))
for k in range(len(profiles)-1):
 for j in range(N):
  a=k*N+j;b=k*N+(j+1)%N;fs.append((a,b,b+N,a+N))
head=objmesh('Acoustic crown • continuous concave shell',vs,fs,bone,'head')
# Recessed dark aperture and fleshy concentric sphincters.
ell('Throat darkness',(0,.018,2.59),(.125,.035,.175),black,'head',24,12)
for k in range(3):
 pts=[]
 for j in range(49):
  a=2*pi*j/48;pts.append(((.12+k*.024)*cos(a),-.045-k*.045,2.59+(.17+k*.031)*sin(a)))
 tube('Throat fold %d'%k,pts,.018,flesh,'head',7)
# Radial membrane ridges: sound funnels, with small carved cartilage plates.
for j in range(24):
 a=2*pi*j/24
 ctrl=[]
 for r,y in [(.97,-.402),(.74,-.32),(.48,-.18),(.36,-.09)]:
  ctrl.append((.36*r*cos(a),y,2.59+.47*r*sin(a)))
 arc('Radial lamella %02d'%j,ctrl,.012,.006,scar if j%3 else flesh,'head',6,4)
# Irregular thin teeth point into the cavity rather than forming a human grin.
for j in range(29):
 a=2*pi*j/29; length=.045+random.random()*.048
 x=.185*cos(a);z=2.59+.25*sin(a);y=-.19
 arc('Vestigial tooth %02d'%j,[(x,y,z),(x*.9,y-.035,z-.035*sin(a)),(x*(1-length/.19),y-.01,z-length*sin(a))],.012,0.001,tooth,'head',6,3)
# Paired swept hearing sails, each open with sculpted folds.
for s in [-1,1]:
 # outer helix, silhouette taller on the left
 high=.09 if s==-1 else 0
 ctrl=[(s*.26,-.15,2.35),(s*.55,-.02,2.52),(s*.73,.08,2.88),(s*.58,.05,3.26+high),(s*.38,-.12,2.95)]
 arc('Auricle outer helix',ctrl,.055,.012,bone,'head',10,7)
 # A radial fan follows the actual helix, leaving no rectangular cut edges.
 outer=smoothpath(ctrl,7)
 anchor=(s*.30,-.09,2.72)
 v=[anchor]+outer
 f=[(0,k+1,k+2) for k in range(len(outer)-1)]
 ob=objmesh('Tympanic sail',v,f,flesh,'head')
 mod=ob.modifiers.new('Membrane thickness','SOLIDIFY');mod.thickness=.009
 for k in [5,10,15,20,25]:
  tip=outer[k]
  arc('Sail cartilage ridge',[anchor,((anchor[0]+tip[0])*.5,-.075,(anchor[2]+tip[2])*.5),tip],.013,.004,bone,'head',6,4)
 # rear skull plating
 ell('Occipital plate',(s*.21,.03,2.64),(.155,.19,.33),skin,'head',16,10)
# Collar plates prevent the skull floating above its neck.
arc('Jaw anchor L',[(-.27,-.15,2.27),(-.18,-.04,2.2),(0,.02,2.28)],.045,.026,bone,'head')
arc('Jaw anchor R',[(.27,-.15,2.27),(.18,-.04,2.2),(0,.02,2.28)],.045,.026,bone,'head')

# Two long arms with sculpted muscle sleeves and four articulated-looking fingers.
landmarks={}
for s,side in [(-1,'L'),(1,'R')]:
 shoulder=(s*.39,.005,2.02); elbow=(s*.61,.04,1.48+(0.06 if s==1 else 0)); wrist=(s*.72,-.15,.91); palm=(s*.74,-.21,.77)
 landmarks[side]=(shoulder,elbow,wrist,palm)
 bn='upper_arm.'+side; fn='forearm.'+side; hn='hand.'+side
 ell('Shoulder cap',shoulder,(.155,.15,.18),skin,bn,18,12)
 arc('Humerus sleeve',[shoulder,(s*.51,.035,1.8),elbow],.115,.067,skin,bn,14,6)
 arc('Humerus ridge',[(s*.45,-.09,1.98),(s*.53,-.07,1.78),(s*.62,-.005,1.5)],.042,.028,bone,bn,9)
 ell('Elbow',elbow,(.075,.085,.09),bone,fn,12,8)
 arc('Ulnar sheath',[elbow,(s*.7,-.01,1.23),wrist],.082,.044,skin,fn,12,6)
 arc('Exposed ulna',[(s*.64,-.04,1.45),(s*.69,-.1,1.2),(s*.72,-.19,.94)],.031,.021,bone,fn,8)
 arc('Forearm sinew',[(s*.6,-.04,1.49),(s*.65,-.14,1.2),wrist],.018,.012,flesh,fn,7)
 ell('Palm',palm,(.091,.055,.15),skin,hn,14,10)
 # thumb and three long fingers with hooked keratin tips
 for j in range(4):
  x=s*(.66+j*.052); z=.79+(.025 if j==0 else 0); yy=-.235
  endz=.39+abs(j-1.5)*.045
  ctrl=[(x,yy,z),(x+s*.018,yy-.035,.61),(x+s*.005,yy-.105,endz),(x-s*.015,yy-.18,endz+.055)]
  arc('Digit %s %d'%(side,j),ctrl,.025,.007,skin,hn,8,5)
  arc('Finger dorsal tendon',[(x,yy-.04,z),(x+s*.015,yy-.062,.61),(x,yy-.13,endz+.02)],.009,.004,bone,hn,6,4)
  arc('Hooked nail',[(x,yy-.12,endz+.02),(x-s*.015,yy-.18,endz+.055),(x-s*.02,yy-.2,endz+.11)],.017,.001,black,hn,7,4)
 # Digitigrade legs. Long shins, hind hock, three toes.
 hip=(s*.19,.08,1.23);knee=(s*.29,-.14,.79);hock=(s*.28,.19,.31);ankle=(s*.28,-.02,.09)
 landmarks['leg'+side]=(hip,knee,hock,ankle)
 tn='thigh.'+side;sn='shin.'+side;ft='foot.'+side
 ell('Hip socket',hip,(.14,.14,.16),skin,tn)
 arc('Thigh',[hip,(s*.27,.0,1.05),knee],.128,.074,skin,tn,14,6)
 arc('Femoral ridge',[(s*.22,-.035,1.23),(s*.3,-.13,1.03),knee],.041,.035,bone,tn,9)
 ell('Knee shield',(s*.29,-.185,.79),(.084,.055,.095),bone,sn,14,8)
 arc('Shin', [knee,(s*.29,.12,.49),hock],.078,.041,skin,sn,12,6)
 arc('Tibial edge',[(s*.29,-.18,.77),(s*.29,.06,.48),(s*.28,.145,.31)],.03,.022,bone,sn,8)
 arc('Hock to heel',[hock,(s*.28,.1,.15),ankle],.047,.06,skin,ft,10)
 for j in range(3):
  x=s*.28+(j-1)*.055
  arc('Ground talon',[(x,.0,.095),(x,-.16,.065),(x+(j-1)*.02,-.26,.035)],.033,.006,bone,ft,8,5)
  arc('Toe keratin',[(x,-.17,.063),(x+(j-1)*.02,-.26,.035),(x+(j-1)*.025,-.29,.018)],.021,.001,black,ft,7,3)
# Asymmetric shoulder bristles and surface creases.
for s in [-1,1]:
 for j in range(4):
  arc('Scapular spur',[(s*(.2+j*.05),.13,1.98),(s*(.24+j*.065),.25,2.08),(s*(.25+j*.08),.29,2.17+j*.025)],.027,.001,bone,'chest',7,4)
for i in range(9):
 x=random.uniform(-.18,.18);z=random.uniform(1.38,1.9)
 arc('Healed hide seam',[(x,.21,z),(x+.035,.225,z+.07),(x+.018,.21,z+.12)],.008,.003,scar,'chest',6,3)

# Apply solidify and join for one draw object with six material slots.
bpy.ops.object.select_all(action='DESELECT')
for ob in parts:
 bpy.context.view_layer.objects.active=ob; ob.select_set(True)
 for mod in list(ob.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
 ob.select_set(False)
for ob in parts:ob.select_set(True)
bpy.context.view_layer.objects.active=body; bpy.ops.object.join(); creature=bpy.context.object;creature.name='Listener • THE HOLLOW CHOIR'
# UVs for a portable baked albedo atlas.
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(angle_limit=math.radians(65),island_margin=.007);bpy.ops.object.mode_set(mode='OBJECT')

# Bone rig, Z-up in Blender, exported as Y-up for Godot.
bpy.ops.object.select_all(action='DESELECT'); armdata=bpy.data.armatures.new('Listener_Skeleton');rig=bpy.data.objects.new('Listener_Rig',armdata);bpy.context.collection.objects.link(rig);bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
def eb(name,h,t,parent=None):
 b=armdata.edit_bones.new(name);b.head=h;b.tail=t
 if parent:b.parent=armdata.edit_bones[parent]
 return b
eb('root',(0,0,0),(0,0,.3));eb('pelvis',(0,.07,1.16),(0,.04,1.45),'root');eb('chest',(0,.04,1.45),(0,0,2.05),'pelvis');eb('neck',(0,0,2.05),(0,-.08,2.38),'chest');eb('head',(0,-.08,2.38),(0,-.08,2.94),'neck')
for side in ['L','R']:
 sh,el,wr,pa=landmarks[side];hi,kn,ho,an=landmarks['leg'+side]
 eb('upper_arm.'+side,sh,el,'chest');eb('forearm.'+side,el,wr,'upper_arm.'+side);eb('hand.'+side,wr,(pa[0],pa[1],.52),'forearm.'+side)
 eb('thigh.'+side,hi,kn,'pelvis');eb('shin.'+side,kn,ho,'thigh.'+side);eb('foot.'+side,ho,(an[0],-.18,.06),'shin.'+side)
bpy.ops.object.mode_set(mode='OBJECT');creature.parent=rig;mod=creature.modifiers.new('Deformation • Listener skeleton','ARMATURE');mod.object=rig
rig.show_in_front=True

# Four deliberately restrained clips, each in-place and loopable except Alert.
bpy.context.view_layer.objects.active=rig
for p in rig.pose.bones:p.rotation_mode='XYZ'
def resetpose():
 for p in rig.pose.bones:p.rotation_euler=(0,0,0);p.location=(0,0,0);p.scale=(1,1,1)
def key(frame):
 for p in rig.pose.bones:
  p.keyframe_insert('rotation_euler',frame=frame,group=p.name);p.keyframe_insert('location',frame=frame,group=p.name);p.keyframe_insert('scale',frame=frame,group=p.name)
clips=[]
def clip(name,end,kind):
 rig.animation_data_create();rig.animation_data.action=bpy.data.actions.new(name)
 for f in range(1,end+1,4):
  resetpose();t=(f-1)/(end-1)*2*pi
  p=rig.pose.bones
  if kind=='idle':
   p['chest'].scale=(1+.018*sin(t),1+.035*sin(t),1+.012*sin(t));p['head'].rotation_euler[1]=.045*sin(t);p['neck'].rotation_euler[0]=.035*sin(t+.5)
   p['forearm.L'].rotation_euler[0]=.04*sin(t+.7);p['hand.R'].rotation_euler[2]=.05*sin(t+1)
  elif kind=='walk':
   p['pelvis'].location.z=.025*cos(2*t);p['chest'].rotation_euler[1]=.045*sin(t)
   for side,offset in [('L',0),('R',pi)]:
    a=sin(t+offset);p['thigh.'+side].rotation_euler[0]=.27*a;p['shin.'+side].rotation_euler[0]=max(0,-a)*.34;p['foot.'+side].rotation_euler[0]=-.12*a
    p['upper_arm.'+side].rotation_euler[0]=-.15*a;p['forearm.'+side].rotation_euler[0]=.06+.08*a
   p['head'].rotation_euler[1]=-.035*sin(t)
  elif kind=='alert':
   w=sin(min(1,(f-1)/12)*pi/2);p['head'].rotation_euler[1]=-.32*w;p['neck'].rotation_euler[0]=-.12*w;p['chest'].rotation_euler[0]=-.045*w
   p['upper_arm.L'].rotation_euler[2]=.13*w;p['forearm.R'].rotation_euler[0]=-.16*w
  elif kind=='sleep':
   p['neck'].rotation_euler[0]=.32;p['head'].rotation_euler[0]=.18;p['chest'].rotation_euler[0]=.13
   p['chest'].scale=(1+.01*sin(t),1+.02*sin(t),1);p['forearm.L'].rotation_euler[0]=.18;p['forearm.R'].rotation_euler[0]=.16
  key(f)
 # Exact closure for looping clips.
 if kind!='alert':
  bpy.context.scene.frame_set(1);key(end)
 action=rig.animation_data.action; track=rig.animation_data.nla_tracks.new();track.name=name;strip=track.strips.new(name,1,action);track.mute=True
 clips.append({'name':name,'frames':end,'loop':kind!='alert'})
clip('Idle_Breathe',81,'idle');clip('Walk_Stalk',41,'walk');clip('Alert_Listen',33,'alert');clip('Sleep_Dormant',97,'sleep')
rig.animation_data.action=None;resetpose();bpy.context.scene.frame_set(1)

# Bake the procedural palette, so exports retain their color without Blender nodes.
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=1
atlas=bpy.data.images.new('Listener_Albedo_2K',width=2048,height=2048,alpha=False)
for m in creature.data.materials:
 nt=m.node_tree;n=nt.nodes;l=nt.links;p=n.get('Principled BSDF');out=n.get('Material Output')
 img=n.new('ShaderNodeTexImage');img.image=atlas;n.active=img
 emit=n.new('ShaderNodeEmission');base=p.inputs['Base Color'].links[0].from_socket;l.new(base,emit.inputs[0]);l.new(emit.outputs[0],out.inputs[0])
bpy.ops.object.select_all(action='DESELECT');creature.select_set(True);bpy.context.view_layer.objects.active=creature
scene.render.bake.margin=8
bpy.ops.object.bake(type='EMIT')
atlas.filepath_raw=OUT+'/Listener_Albedo_2K.png';atlas.file_format='PNG';atlas.save();atlas.pack()
for m in creature.data.materials:
 nt=m.node_tree;n=nt.nodes;l=nt.links;p=n.get('Principled BSDF');out=n.get('Material Output');l.new(p.outputs[0],out.inputs[0]);img=next(x for x in n if x.type=='TEX_IMAGE');l.new(img.outputs['Color'],p.inputs['Base Color'])

# Export only rig and mesh. NLA strips supply named glTF animations.
for tr in rig.animation_data.nla_tracks:tr.mute=False
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);creature.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=OUT+'/Listener.glb',export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_nla_strips=True,export_skins=True,export_texcoords=True,export_normals=True,export_yup=True)
for tr in rig.animation_data.nla_tracks:tr.mute=True
resetpose()
# Presentation collection is excluded from the GLB and separated in the source.
pres=bpy.data.collections.new('STUDIO • presentation only');scene.collection.children.link(pres)
def studio(ob):
 for c in list(ob.users_collection):c.objects.unlink(ob)
 pres.objects.link(ob)
 return ob
floor=material('Studio floor',(.014,.019,.022),(.035,.045,.049),.82,4)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.015));ground=bpy.context.object;ground.name='Studio floor';ground.data.materials.append(floor);studio(ground)
# Thin worn platform, no visual clutter.
bpy.ops.mesh.primitive_cylinder_add(vertices=96,radius=1.18,depth=.055,location=(0,0,-.045));plinth=bpy.context.object;plinth.name='Specimen plinth';plinth.data.materials.append(black);studio(plinth)
bev=plinth.modifiers.new('Soft edge','BEVEL');bev.width=.018;bev.segments=3

def aim(ob,pt):ob.rotation_euler=(Vector(pt)-ob.location).to_track_quat('-Z','Y').to_euler()
def area(name,loc,power,color,size,target=(0,0,1.7)):
 data=bpy.data.lights.new(name,'AREA');data.energy=power;data.color=color;data.shape='DISK';data.size=size;ob=bpy.data.objects.new(name,data);pres.objects.link(ob);ob.location=loc;aim(ob,target)
area('Key • warm softbox',(-3,-4.5,5.3),440,(1,.79,.60),4)
area('Fill • cool bounce',(3,-2.5,2.7),160,(.45,.67,.8),3)
area('Rim • red edge',(1.7,2,3.9),800,(1,.12,.10),2.5)
area('Crown separation',(-2,1,4.8),700,(.37,.68,.78),2)
camdata=bpy.data.cameras.new('Portrait camera');cam=bpy.data.objects.new('Portrait camera',camdata);pres.objects.link(cam);scene.camera=cam;cam.location=(4,-7,3.1);aim(cam,(0,-.01,1.65));camdata.type='ORTHO';camdata.ortho_scale=4.18
scene.world.color=(.035,.035,.035);scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=True
scene.render.resolution_x=1250;scene.render.resolution_y=1500;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
scene.render.fps=24;scene.frame_start=1;scene.frame_end=97
# Open into a useful material view with the model selected.
bpy.ops.object.select_all(action='DESELECT');creature.select_set(True);bpy.context.view_layer.objects.active=creature
for screen in bpy.data.screens:
 for a in screen.areas:
  if a.type=='VIEW_3D':
   a.spaces.active.region_3d.view_distance=5.3;a.spaces.active.region_3d.view_location=(0,0,1.65);a.spaces.active.shading.type='MATERIAL'
rig['asset']='THE HOLLOW CHOIR / Listener';rig['forward']='Blender -Y; glTF +Z';rig['clips']='Idle_Breathe, Walk_Stalk, Alert_Listen, Sleep_Dormant'
creature['notes']='Original procedural creature. No source mesh or textures from Sketchfab. Presentation collection excluded from GLB.'
triangles=sum(len(p.vertices)-2 for p in creature.data.polygons)
meta={'vertices':len(creature.data.vertices),'triangles':triangles,'bones':len(rig.data.bones),'materials':len(creature.data.materials),'animations':clips,'height_m':max(v.co.z for v in creature.data.vertices)-min(v.co.z for v in creature.data.vertices)}
open(OUT+'/asset_manifest.json','w').write(json.dumps(meta,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/Listener.blend')
scene.render.filepath=OUT+'/Listener_Beauty.png';bpy.ops.render.render(write_still=True)
# Additional orthographic views for inspection.
scene.cycles.samples=24;scene.render.resolution_x=950;scene.render.resolution_y=1200
for label,loc in [('Front',(0,-8,2)),('Back',(0,8,2)),('Side',(8,0,2))]:
 cam.location=loc;aim(cam,(0,0,1.65));camdata.ortho_scale=3.9;scene.render.filepath=OUT+'/Listener_'+label+'.png';bpy.ops.render.render(write_still=True)
print('ASSET_COMPLETE',json.dumps(meta))
