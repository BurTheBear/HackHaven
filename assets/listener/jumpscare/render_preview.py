import bpy, os
O=os.path.dirname(os.path.abspath(__file__))
bpy.ops.wm.open_mainfile(filepath=O+'/Listener_Jumpscare.blend')
s=bpy.context.scene
prefs=bpy.context.preferences.addons['cycles'].preferences
prefs.compute_device_type='METAL';prefs.get_devices()
for device in prefs.devices:device.use=device.type=='METAL'
s.cycles.device='GPU'
if not s.sequence_editor:
 s.sequence_editor_create().strips.new_sound('CC0 jumpscare mix',O+'/Jumpscare_Audio.wav',channel=1,frame_start=1)
bpy.ops.file.pack_all()
s.frame_set(38);s.render.filepath=O+'/frames/'
bpy.ops.wm.save_as_mainfile(filepath=O+'/Listener_Jumpscare.blend')
s.frame_start=1;s.frame_end=79
while os.path.exists(O+'/frames/%04d.png'%s.frame_start):s.frame_start+=1
bpy.ops.render.render(animation=True)
