struct SkeletonVertexAttribute {
    u8 joints[4];
    f32 weights[4];
}

struct CascadeConfig {
    f32 split_dist;
    f32 bias;
    f32 slope_bias;
}

struct Vertex {
    Vec3 position;
    f32 uv_x;
    Vec3 normal;
    f32 uv_y;
    Vec4 color;
    Vec4 tangent;
}

struct Point_Light {
    Vec3 color;
    f32 radius;
    Vec3 world_pos;
    f32 lumens;
}

struct Sh_Coefficients {
    Vec4 coef[9];
}

struct PBR_Material {
    Tex2D base_color;
    Tex2D normal_map;
    Tex2D ao_roughness_metallic;
}

struct DrawPushConstants {
    GlobalData *global_data;
    Vertex *vertex_buffer;
    Mat4x4 *model_matrices;
    PBR_Material *materials;
    u32 model_index;
    u32 material_index;
    u32 num_cascades;
}

struct DrawShadowDepthPushConstants {
    Vertex *vertex_buffer;
    Mat4x4 *model_matrices;
    GlobalData *global_data;
    u32 model_index;
    u32 cascade_index;
}

struct SkinningPushConstants {
    Vertex *input_vertex_buffer;
    Vertex *output_vertex_buffer;
    Mat4x4 *joint_matrices;
    SkeletonVertexAttribute *attrs;
    u32 vertex_count;
}

struct SkyboxPushConstants {
    Vertex *vertex_buffer;
    GlobalData *global_data;
}

struct Environment {
    Sh_Coefficients *sh_volume;
    Point_Light *point_lights;
    u32 num_point_lights;
}

struct GlobalData {
    Mat4x4 *cascade_world_to_shadows;
    CascadeConfig *cascade_configs;
    Mat4x4 view_to_clip;
    Mat4x4 world_to_view;
    Vec3 sun_color;
    Vec3 sky_color;
    Vec3 camera_pos;
    Vec3 sun_direction;
    Environment environment;
}

