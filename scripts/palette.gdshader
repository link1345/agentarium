shader_type canvas_item;
uniform float source_hue = 0.72;
uniform float target_hue = 0.72;
uniform float hue_tolerance = 0.11;
uniform bool enabled = true;
vec3 rgb2hsv(vec3 c) {
 vec4 K=vec4(0.,-1./3.,2./3.,-1.);
 vec4 p=mix(vec4(c.bg,K.wz),vec4(c.gb,K.xy),step(c.b,c.g));
 vec4 q=mix(vec4(p.xyw,c.r),vec4(c.r,p.yzx),step(p.x,c.r));
 float d=q.x-min(q.w,q.y),e=1.e-10;
 return vec3(abs(q.z+(q.w-q.y)/(6.*d+e)),d/(q.x+e),q.x);
}
vec3 hsv2rgb(vec3 c) {
 vec3 p=abs(fract(c.xxx+vec3(0.,2./3.,1./3.))*6.-3.);
 return c.z*mix(vec3(1.),clamp(p-1.,0.,1.),c.y);
}
void fragment() {
 vec4 pixel=texture(TEXTURE,UV);
 vec3 hsv=rgb2hsv(pixel.rgb);
 float delta=fract(hsv.x-source_hue+0.5)-0.5;
 if(enabled && abs(delta)<=hue_tolerance && hsv.y>=0.12 && hsv.z>=0.45) {
   hsv.x=fract(target_hue+delta+1.);
   pixel.rgb=hsv2rgb(hsv);
 }
 COLOR=pixel;
}
