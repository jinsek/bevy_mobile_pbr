#import bevy_pbr::{
    pbr_functions,
    pbr_types,
    prepass_utils,
    lighting,
    clustered_forward as clustering,
    shadows,
    ambient,
    mesh_bindings::mesh,
    mesh_view_bindings as view_bindings,
    mesh_view_types,
    mesh_types::{MESH_FLAGS_SHADOW_RECEIVER_BIT, MESH_FLAGS_TRANSMITTED_SHADOW_RECEIVER_BIT},
}

#ifdef ENVIRONMENT_MAP
#import bevy_pbr::environment_map
#endif

#import bevy_pbr::forward_io::VertexOutput
#import bevy_pbr::pbr_bindings::{base_color_texture, base_color_sampler, 
    metallic_roughness_texture, metallic_roughness_sampler}

// prepare a basic PbrInput from the vertex stage output, mesh binding and view binding
fn pbr_input_from_vertex_output(
    in: VertexOutput,
    is_front: bool,
    double_sided: bool,
) -> pbr_types::PbrInput {
    var pbr_input: pbr_types::PbrInput = pbr_types::pbr_input_new();

    pbr_input.flags = mesh[in.instance_index].flags;
    pbr_input.is_orthographic = view_bindings::view.projection[3].w == 1.0;
    pbr_input.V = pbr_functions::calculate_view(in.world_position, pbr_input.is_orthographic);
    pbr_input.frag_coord = in.position;
    pbr_input.world_position = in.world_position;

#ifdef VERTEX_COLORS
    pbr_input.material.base_color = in.color;
#endif

    pbr_input.world_normal = pbr_functions::prepare_world_normal(
        in.world_normal,
        double_sided,
        is_front,
    );

    pbr_input.N = normalize(pbr_input.world_normal);
    return pbr_input;
}

fn apply_normal_mapping(
    world_normal: vec3<f32>,
    double_sided: bool,
    is_front: bool,
    world_tangent: vec4<f32>,
    uv: vec2<f32>,
    normal_t: vec2<f32>,
    mip_bias: f32,
) -> vec3<f32> {
    var N: vec3<f32> = world_normal;
    var T: vec3<f32> = world_tangent.xyz;
    var B: vec3<f32> = world_tangent.w * cross(N, T);

    var Nt = vec3<f32>(normal_t.rg * 2.0 - 1.0, 0.0);
    Nt.z = sqrt(1.0 - Nt.x * Nt.x - Nt.y * Nt.y);
    //dx 12
    //Nt.y = -Nt.y;
    if double_sided && !is_front {
        Nt = -Nt;
    }
    N = Nt.x * T + Nt.y * B + Nt.z * N;
    return normalize(N);
}

// Prepare a full PbrInput by sampling all textures to resolve
// the material members
fn pbr_input_from_mobile_pbr_material(
    in: VertexOutput,
    is_front: bool,
) -> pbr_types::PbrInput {
    var pbr_input: pbr_types::PbrInput = pbr_input_from_vertex_output(in, is_front, false);
    
    let NdotV = max(dot(pbr_input.N, pbr_input.V), 0.0001);
    var uv = in.uv;
    pbr_input.material.base_color = textureSampleBias(base_color_texture, base_color_sampler, uv, view_bindings::view.mip_bias);
   
    let normal_metallic_roughness = textureSampleBias(metallic_roughness_texture, metallic_roughness_sampler, uv, view_bindings::view.mip_bias);
    // Sampling from GLTF standard channels for now
    pbr_input.material.metallic = normal_metallic_roughness.b;
    pbr_input.material.perceptual_roughness = normal_metallic_roughness.g;
    pbr_input.N = apply_normal_mapping(
        pbr_input.world_normal,
        false,
        is_front,
        in.world_tangent,
        uv,
        normal_metallic_roughness.ra,
        view_bindings::view.mip_bias);
    return pbr_input;
}

fn apply_mobile_pbr_lighting(
    in: pbr_types::PbrInput,
) -> vec4<f32> {
    var output_color: vec4<f32> = in.material.base_color;

    // TODO use .a for exposure compensation in HDR
    let emissive = in.material.emissive;

    // calculate non-linear roughness from linear perceptualRoughness
    let metallic = in.material.metallic;
    let perceptual_roughness = in.material.perceptual_roughness;
    let roughness = lighting::perceptualRoughnessToRoughness(perceptual_roughness);
    let diffuse_occlusion = in.diffuse_occlusion;
    let specular_occlusion = in.specular_occlusion;

    // Neubelt and Pettineo 2013, "Crafting a Next-gen Material Pipeline for The Order: 1886"
    let NdotV = max(dot(in.N, in.V), 0.0001);

    // Remapping [0,1] reflectance to F0
    // See https://google.github.io/filament/Filament.html#materialsystem/parameterization/remapping
    let reflectance = in.material.reflectance;
    let F0 = 0.16 * reflectance * reflectance * (1.0 - metallic) + output_color.rgb * metallic;

    // Diffuse strength is inversely related to metallicity, specular and diffuse transmission
    let diffuse_color = output_color.rgb * (1.0 - metallic);
    let R = reflect(-in.V, in.N);
    let f_ab = lighting::F_AB(perceptual_roughness, NdotV);
    var direct_light: vec3<f32> = vec3<f32>(0.0);
    let view_z = dot(vec4<f32>(
        view_bindings::view.inverse_view[0].z,
        view_bindings::view.inverse_view[1].z,
        view_bindings::view.inverse_view[2].z,
        view_bindings::view.inverse_view[3].z
    ), in.world_position);
    let cluster_index = clustering::fragment_cluster_index(in.frag_coord.xy, view_z, in.is_orthographic);
    let offset_and_counts = clustering::unpack_offset_and_counts(cluster_index);

    // Point lights (direct)
    for (var i: u32 = offset_and_counts[0]; i < offset_and_counts[0] + offset_and_counts[1]; i = i + 1u) {
        let light_id = clustering::get_light_id(i);
        var shadow: f32 = 1.0;
        if ((in.flags & MESH_FLAGS_SHADOW_RECEIVER_BIT) != 0u
                && (view_bindings::point_lights.data[light_id].flags & mesh_view_types::POINT_LIGHT_FLAGS_SHADOWS_ENABLED_BIT) != 0u) {
            shadow = shadows::fetch_point_shadow(light_id, in.world_position, in.world_normal);
        }
        let light_contrib = lighting::point_light(in.world_position.xyz, light_id, roughness, NdotV, in.N, in.V, R, F0, f_ab, diffuse_color);
        direct_light += light_contrib * shadow;
    }

    // Spot lights (direct)
    for (var i: u32 = offset_and_counts[0] + offset_and_counts[1]; i < offset_and_counts[0] + offset_and_counts[1] + offset_and_counts[2]; i = i + 1u) {
        let light_id = clustering::get_light_id(i);

        var shadow: f32 = 1.0;
        if ((in.flags & MESH_FLAGS_SHADOW_RECEIVER_BIT) != 0u
                && (view_bindings::point_lights.data[light_id].flags & mesh_view_types::POINT_LIGHT_FLAGS_SHADOWS_ENABLED_BIT) != 0u) {
            shadow = shadows::fetch_spot_shadow(light_id, in.world_position, in.world_normal);
        }
        let light_contrib = lighting::spot_light(in.world_position.xyz, light_id, roughness, NdotV, in.N, in.V, R, F0, f_ab, diffuse_color);
        direct_light += light_contrib * shadow;
    }

    // directional lights (direct)
    let n_directional_lights = view_bindings::lights.n_directional_lights;
    for (var i: u32 = 0u; i < n_directional_lights; i = i + 1u) {
        // check the directional light render layers intersect the view render layers
        // note this is not necessary for point and spot lights, as the relevant lights are filtered in `assign_lights_to_clusters`
        let light = &view_bindings::lights.directional_lights[i];
        if ((*light).render_layers & view_bindings::view.render_layers) == 0u {
            continue;
        }

        var shadow: f32 = 1.0;
        if ((in.flags & MESH_FLAGS_SHADOW_RECEIVER_BIT) != 0u
                && (view_bindings::lights.directional_lights[i].flags & mesh_view_types::DIRECTIONAL_LIGHT_FLAGS_SHADOWS_ENABLED_BIT) != 0u) {
            shadow = shadows::fetch_directional_shadow(i, in.world_position, in.world_normal, view_z);
        }
        var light_contrib = lighting::directional_light(i, roughness, NdotV, in.N, in.V, R, F0, f_ab, diffuse_color);
#ifdef DIRECTIONAL_LIGHT_SHADOW_MAP_DEBUG_CASCADES
        light_contrib = shadows::cascade_debug_visualization(light_contrib, i, view_z);
#endif
        direct_light += light_contrib * shadow;
    }

    var indirect_light = vec3(0.0f);
#ifdef LIGHTMAP
    if (all(indirect_light == vec3(0.0f))) {
        indirect_light += in.lightmap_light * diffuse_color;
    }
#endif

    // Ambient light (indirect), simplified
    indirect_light += (diffuse_color + F0 * specular_occlusion) * view_bindings::lights.ambient_color.rgb * diffuse_occlusion;

    let emissive_light = emissive.rgb * output_color.a;

    // Total light
    output_color = vec4<f32>(
        view_bindings::view.exposure * (direct_light + indirect_light + emissive_light),
        output_color.a
    );
    return output_color;
}