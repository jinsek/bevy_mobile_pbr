#import bevy_pbr::pbr_functions::alpha_discard;
#import "shaders/mobile_pbr_fragment.wgsl"::{pbr_input_from_mobile_pbr_material,
    apply_mobile_pbr_lighting}
#import bevy_pbr::{
    forward_io::{VertexOutput, FragmentOutput},
}

@fragment
fn fragment(
    in: VertexOutput,
    @builtin(front_facing) is_front: bool,
) -> FragmentOutput {
    // generate a PbrInput struct from the StandardMaterial bindings
    var pbr_input = pbr_input_from_mobile_pbr_material(in, is_front);

    var out: FragmentOutput;
    out.color = apply_mobile_pbr_lighting(pbr_input);
    return out;
}
