# bevy_mobile_pbr
bevy engine 0.13 fixed the pbr material performance problem on android platform.
But, it's still a pc/console spec material, sampled too many textures and its ambient lighting algorithm way too complicate for mobile platform.
this repo merged metallic& roughness components with normal map, simplified the ambient lighting function, make the fps up to 60fps on a XiaoMi Mix2s android phone.
this is not the final solutin for mobile pbr materials, just a test for customizing pbr materials, might be a good reference for someone who want to do similar thing.

# usage

install rust & bevy
build with cmd: cargo apk run -p bevy_mobile_pbr
