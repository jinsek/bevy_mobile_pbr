use bevy::{
    input::touch::TouchPhase,
    diagnostic::DiagnosticsStore,
    diagnostic::FrameTimeDiagnosticsPlugin,
    prelude::*,
    asset::{Asset, Handle},
    reflect::TypePath,
    render::{render_resource::*, texture::Image},
    window::{ApplicationLifetime, WindowMode},
};
use std::f32::consts::*;

// the `bevy_main` proc_macro generates the required boilerplate for iOS and Android
#[bevy_main]
fn main() {
    let mut app = App::new();
    app.add_plugins(DefaultPlugins.set(WindowPlugin {
        primary_window: Some(Window {
            resizable: false,
            mode: WindowMode::BorderlessFullscreen,
            ..default()
        }),
        ..default()
    }))    
    .add_event::<MyEvent>()
    .add_plugins(MaterialPlugin::<MobilePBRMaterial>::default())
    .add_systems(Startup, (setup_env, setup_music))
    .add_systems(Update, (animate_light_direction, fps_text_update_system, touch_camera, 
        button_handler, handle_lifetime, event_listener))
    .add_plugins(FrameTimeDiagnosticsPlugin::default());

    // MSAA makes some Android devices panic, this is under investigation
    // https://github.com/bevyengine/bevy/issues/8229
    #[cfg(target_os = "android")]
    app.insert_resource(Msaa::Off);

    app.run();
}

fn touch_camera(
    windows: Query<&Window>,
    mut touches: EventReader<TouchInput>,
    mut camera: Query<&mut Transform, With<Camera3d>>,
    mut last_position: Local<Option<Vec2>>,
) {
    let window = windows.single();

    for touch in touches.read() {
        if touch.phase == TouchPhase::Started {
            *last_position = None;
        }
        if let Some(last_position) = *last_position {
            if last_position.y < window.height() * 0.8 {
                let mut transform = camera.single_mut();
                *transform = Transform::from_xyz(
                    transform.translation.x
                        + (touch.position.x - last_position.x) / window.width() * 5.0,
                    transform.translation.y,
                    transform.translation.z
                        + (touch.position.y - last_position.y) / window.height() * 5.0,
                )
                .looking_at(Vec3::new(0.0, 0.3, 0.0), Vec3::Y);                
            }
        }
        *last_position = Some(touch.position);
    }
}
/// set up a simple 3D scene
fn setup_env(
    mut commands: Commands,
    asset_server: Res<AssetServer>,
) {    
    commands.spawn((
        Camera3dBundle {
            transform: Transform::from_xyz(0.7, 0.7, 1.0)
            .looking_at(Vec3::new(0.0, 0.3, 0.0), Vec3::Y),
            ..default()
        },
    ));    
    commands.spawn(DirectionalLightBundle {
        directional_light: DirectionalLight {
            illuminance: 2000.0,
            shadows_enabled: false,
            ..default()
        },
        ..default()
    });
    
    commands.spawn(SceneBundle {
        scene: asset_server.load("models/FlightHelmet/FlightHelmet.gltf#Scene0"),
        ..default()
    });
    // labels
    commands.spawn((
        TextBundle::from_section(
            " ",
            TextStyle {
                font_size: 18.0,
                ..default()
            },
        )
        .with_style(Style {
            position_type: PositionType::Absolute,
            top: Val::Px(20.0),
            left: Val::Px(100.0),
            ..default()
        }),
        FpsText,
    ));
    // Test ui
    commands
        .spawn(ButtonBundle {
            style: Style {
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                position_type: PositionType::Absolute,
                left: Val::Px(50.0),
                right: Val::Px(50.0),
                bottom: Val::Px(50.0),
                ..default()
            },
            ..default()
        })
        .with_children(|b| {
            b.spawn(
                TextBundle::from_section(
                    "Switch Material",
                    TextStyle {
                        font_size: 30.0,
                        color: Color::BLACK,
                        ..default()
                    },
                ),
            );
        });   
}

fn animate_light_direction(
    time: Res<Time>,
    mut query: Query<&mut Transform, With<DirectionalLight>>,
) {
    for mut transform in &mut query {
        transform.rotation = Quat::from_euler(
            EulerRot::ZYX,
            0.0,
            time.elapsed_seconds() * PI / 5.0,
            -FRAC_PI_4,
        );
    }
}

#[derive(Event)]
struct MyEvent {
    pub message: String,
}
fn button_handler(
    mut interaction_query: Query<
        (&Interaction, &mut BackgroundColor),
        (Changed<Interaction>, With<Button>),
    >,    
    mut my_events: EventWriter<MyEvent>,
) {
    for (interaction, mut color) in &mut interaction_query {
        match *interaction {
            Interaction::Pressed => {
                *color = Color::BLUE.into();    
                my_events.send(MyEvent {
                    message: "MyEvent just happened!".to_string(),
                }); 
            }
            Interaction::Hovered => {
                *color = Color::GRAY.into();
            }
            Interaction::None => {
                *color = Color::WHITE.into();
            }
        }
    }
}

fn setup_music(asset_server: Res<AssetServer>, mut commands: Commands) {
    commands.spawn(AudioBundle {
        source: asset_server.load("sounds/Windless Slopes.ogg"),
        settings: PlaybackSettings::LOOP,
    });
}

// Pause audio when app goes into background and resume when it returns.
// This is handled by the OS on iOS, but not on Android.
fn handle_lifetime(
    mut lifetime_events: EventReader<ApplicationLifetime>,
    music_controller: Query<&AudioSink>,
) {
    for event in lifetime_events.read() {
        match event {
            ApplicationLifetime::Suspended => music_controller.single().pause(),
            ApplicationLifetime::Resumed => music_controller.single().play(),
            ApplicationLifetime::Started => (),
        }
    }
}

fn fps_text_update_system(
    diagnostics: Res<DiagnosticsStore>,
    mut query: Query<&mut Text, With<FpsText>>,
) {
    for mut text in &mut query {
        // try to get a "smoothed" FPS value from Bevy
        if let Some(value) = diagnostics
            .get(&FrameTimeDiagnosticsPlugin::FPS)
            .and_then(|fps| fps.average())
        {
            // Format the number as to leave space for 4 digits, just in case,
            // right-aligned and rounded. This helps readability when the
            // number changes rapidly.
            text.sections[0].value = format!("FPS : {value:>4.0}");

            // Let's make it extra fancy by changing the color of the
            // text according to the FPS value:
            text.sections[0].style.color = if value >= 120.0 {
                // Above 120 FPS, use green color
                Color::rgb(0.0, 1.0, 0.0)
            } else if value >= 60.0 {
                // Between 60-120 FPS, gradually transition from yellow to green
                Color::rgb(
                    (1.0 - (value - 60.0) / (120.0 - 60.0)) as f32,
                    1.0,
                    0.0,
                )
            } else if value >= 30.0 {
                // Between 30-60 FPS, gradually transition from red to yellow
                Color::rgb(
                    1.0,
                    ((value - 30.0) / (60.0 - 30.0)) as f32,
                    0.0,
                )
            } else {
                // Below 30 FPS, use red color
                Color::rgb(1.0, 0.0, 0.0)
            }
        } else {
            // display "N/A" if we can't get a FPS measurement
            // add an extra space to preserve alignment
            text.sections[0].value = "FPS : N/A".into();
            text.sections[0].style.color = Color::WHITE;
        }
    }
}

#[derive(Component)]
struct FpsText;

fn event_listener(
    mut events: EventReader<MyEvent>,
    handles: Query<(Entity, &Handle<StandardMaterial>)>,
    pbr_materials: Res<Assets<StandardMaterial>>,
    mut custom_materials: ResMut<Assets<MobilePBRMaterial>>,    
    mut camera: Query<&mut Transform, With<Camera3d>>,
    mut cmds: Commands,
) {
    for my_event in events.read() {
        let mut transform = camera.single_mut();
        *transform = Transform::from_xyz(0.7, 0.7, 1.0)
            .looking_at(Vec3::new(0.0, 0.3, 0.0), Vec3::Y);
        info!("{}", my_event.message);
        for (entity, material_handle) in handles.iter() {
            let Some(material) = pbr_materials.get(material_handle) else { continue; };
            let custom = custom_materials.add(material);
            cmds.entity(entity).insert(custom).remove::<Handle<StandardMaterial>>();
        }
    }
}

#[derive(Asset, TypePath, AsBindGroup, Debug, Clone)]
pub struct MobilePBRMaterial {    
    #[texture(1)]
    #[sampler(2)]
    pub base_color_texture: Option<Handle<Image>>,
    #[texture(5)]
    #[sampler(6)]
    pub normal_metallic_roughness_texture: Option<Handle<Image>>,  
    pub cull_mode: Option<Face>,
    pub alpha_mode: AlphaMode,
}

impl Default for MobilePBRMaterial {
    fn default() -> Self {
        MobilePBRMaterial {
            base_color_texture: None,
            normal_metallic_roughness_texture: None,
            cull_mode: Some(Face::Back),
            alpha_mode: AlphaMode::Opaque,
        }
    }
}

impl Material for MobilePBRMaterial {
    fn fragment_shader() -> ShaderRef {
        "shaders/mobile_pbr_material.wgsl".into()
    }

    fn alpha_mode(&self) -> AlphaMode {
        self.alpha_mode
    }
}

impl<'a> From<&'a StandardMaterial> for MobilePBRMaterial {
    fn from(value: &'a StandardMaterial) -> Self {
        MobilePBRMaterial {
            base_color_texture: value.base_color_texture.clone(),
            normal_metallic_roughness_texture: value.metallic_roughness_texture.clone(),
            cull_mode: Some(Face::Back),
            alpha_mode: value.alpha_mode.clone(),
        }
    }
}