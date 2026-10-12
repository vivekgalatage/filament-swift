#ifndef FILAMENT_C_H
#define FILAMENT_C_H

// Core Filament Engine Headers
#include <filament/Engine.h>
#include <filament/Renderer.h>
#include <filament/Scene.h>
#include <filament/View.h>
#include <filament/Camera.h>
#include <filament/SwapChain.h>
#include <filament/Viewport.h>
#include <filament/IndexBuffer.h>
#include <filament/VertexBuffer.h>
#include <filament/RenderableManager.h>
#include <filament/TransformManager.h>
#include <filament/LightManager.h>
#include <filament/Material.h>
#include <filament/MaterialInstance.h>
#include <filament/Skybox.h>
#include <filament/IndirectLight.h>
#include <filament/Color.h>

// gltfio GLB / glTF 2.0 Asset Loader Headers
#include <gltfio/AssetLoader.h>
#include <gltfio/FilamentAsset.h>
#include <gltfio/ResourceLoader.h>
#include <gltfio/Animator.h>
#include <gltfio/materials/uberarchive.h>

// Platform Driver / Backend
#include <backend/DriverEnums.h>
#include <backend/PixelBufferDescriptor.h>

// Utilities & Math
#include <utils/EntityManager.h>
#include <utils/Entity.h>
#include <math/mat4.h>
#include <math/vec3.h>
#include <math/vec4.h>

#endif // FILAMENT_C_H
