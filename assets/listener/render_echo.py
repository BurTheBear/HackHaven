import bpy,os
O=os.path.dirname(os.path.abspath(__file__))
bpy.ops.wm.open_mainfile(filepath=O+"/Listener.blend")
s=bpy.context.scene
ob=next(o for o in s.objects if o.type=="MESH" and "HOLLOW" in o.name)
# Echo silhouette image. Presentation shader only, separate from GLB materials.
echo=bpy.data.materials.new('Echo preview red');echo.use_nodes=True;n=echo.node_tree.nodes;n.clear();l=echo.node_tree.links
out=n.new('ShaderNodeOutputMaterial');em=n.new('ShaderNodeEmission');em.inputs[0].default_value=(1,.025,.055,1)
layer=n.new('ShaderNodeLayerWeight');r=n.new('ShaderNodeValToRGB');r.color_ramp.elements[0].position=.12;r.color_ramp.elements[0].color=(.015,.015,.015,1);r.color_ramp.elements[1].position=.8;r.color_ramp.elements[1].color=(.85,.85,.85,1)
l.new(layer.outputs['Facing'],r.inputs[0]);l.new(r.outputs[0],em.inputs['Strength']);l.new(em.outputs[0],out.inputs[0])
for i in range(len(ob.data.materials)):ob.data.materials[i]=echo
for o in s.objects:
 if o.type=='LIGHT':o.hide_render=True
 if o.type=='MESH' and o!=ob:o.hide_render=True
s.world.use_nodes=True;s.world.node_tree.nodes.get("Background").inputs[0].default_value=(0,0,0,1);s.world.node_tree.nodes.get("Background").inputs[1].default_value=0;s.render.filepath=O+'/Listener_Echo.png';s.render.resolution_x=1000;s.render.resolution_y=1200;s.cycles.samples=16
bpy.ops.render.render(write_still=True)
print('FINALIZE_COMPLETE')
