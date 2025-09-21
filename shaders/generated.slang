import bindless;
import types;

struct PostProcessingPushConstants {
    RWImage2D resolved_image;
    Image3D<Vec3> tony_mc_mapface;
    Sampler sampler;
}

struct PBR_Material {
    Image2D base_color;
    Image2D normal_map;
    Image2D ao_roughness_metallic;
}

struct CascadeConfig {
    f32 split_dist;
    f32 bias;
    f32 slope_bias;
}

struct SkeletonVertexAttribute {
    u8 joints[4];
    f32 weights[4];
}

struct Point_Light {
    Vec3 color;
    f32 radius;
    Vec3 world_pos;
    f32 lumens;
}

struct Vertex {
    Vec3 position;
    f32 uv_x;
    Vec3 normal;
    f32 uv_y;
    Vec4 color;
    Vec4 tangent;
}

struct ShCoefficients {
    Vec4 coef[9];
}

struct DrawPushConstants {
    Ptr<GlobalData> global_data;
    Ptr<Vertex> vertex_buffer;
    Ptr<Mat4x4> model_matrices;
    Ptr<PBR_Material> materials;
    u32 model_index;
    u32 num_cascades;
    u32 material_index;
    Image2DArray<f32> shadow_depth;
    SamplerComparison shadow_sampler;
}

struct DrawShadowDepthPushConstants {
    Ptr<Vertex> vertex_buffer;
    Ptr<Mat4x4> model_matrices;
    Ptr<GlobalData> global_data;
    u32 model_index;
    u32 cascade_index;
}

struct SkinningPushConstants {
    Ptr<Vertex> input_vertex_buffer;
    Ptr<Vertex> output_vertex_buffer;
    Ptr<Mat4x4> joint_matrices;
    Ptr<SkeletonVertexAttribute> attrs;
    u32 vertex_count;
}

struct SkyboxPushConstants {
    Ptr<Vertex> vertex_buffer;
    Ptr<GlobalData> global_data;
}

struct Environment {
    Ptr<ShCoefficients> sh_volume;
    Ptr<Point_Light> point_lights;
    u32 num_point_lights;
    ImageCube env_map;
    Image2D dfg;
    Sampler env_sampler;
}

struct GlobalData {
    Environment environment;
    Ptr<Mat4x4> cascade_world_to_shadows;
    Ptr<CascadeConfig> cascade_configs;
    Mat4x4 view_to_clip;
    Mat4x4 world_to_view;
    Vec3 sun_color;
    Vec3 sky_color;
    Vec3 camera_pos;
    Vec3 sun_direction;
    Sampler default_sampler;
}

