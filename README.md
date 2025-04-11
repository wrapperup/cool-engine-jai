# cool engine
![image](https://github.com/user-attachments/assets/0e3af819-ab20-4298-9110-d058bb5e4003)

Toy engine + Vulkan renderer I built for fun to learn Odin language, then ported to Jai (to utilize it's awesome metaprogramming features).

### Features
- Sparse entity system (ECS-lite)
- First person player controller based on Unreal character movement
- Skeletal meshes and animation
- Bindless System (see `shaders/text.slang` for a simple example!)
- - Bindless versions of `Texture`, `SamplerState` and `SamplerComparisonState` as handles, while keeping the usage the same.
- - Buffers use BDA
- glTF loading of meshes and skeletal meshes
- Physics (with Physx 5.1)

### Renderer Features
- PBR + IBL + HDR based on [Filament](https://google.github.io/filament/Filament.md.html)
- Point lights
- Tonemapping (tony-mc-mapface)
- CSM
- Compute skinning
- Tools for baking IBL (irradiance SH and specular cubemaps)

### Screenshots

## Dependencies

All the dependencies for this project are included as git submodules. Some of them are forked from another repo!
 
 - [jai-libktx](https://github.com/wrapperup/jai-libktx)
 - [jai-mikktspace](https://github.com/wrapperup/jai-mikktspace)
 - [slang-jai](https://github.com/rytc/slang-jai)
 - [jai-vulkan](https://gitlab.com/Stowy/jai-vulkan)
 - [jai-vma](https://gitlab.com/Stowy/jai-vma)
 - [jai-imgui](https://gitlab.com/Stowy/jai-imgui)
 - [JaiPhysX](https://github.com/kujukuju/JaiPhysX)
 - [gltf_parser](https://github.com/wrapperup/gltf_parser) This is forked from [here](https://github.com/kooparse/gltf_parser).
 - [miniaudio-jai](https://github.com/kooparse/miniaudio-jai).
