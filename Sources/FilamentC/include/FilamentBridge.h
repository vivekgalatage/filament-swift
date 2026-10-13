#pragma once

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#undef min
#undef max
#undef near
#undef far
#endif

#include <utils/Entity.h>

#include <stddef.h>
#include <stdint.h>

namespace filament {
    class Engine;
    class Renderer;
    class Scene;
    class View;
    class Camera;
    class SwapChain;
    class IndirectLight;
    class ColorGrading;
    class Material;
    class MaterialInstance;

#ifndef TNT_FILAMENT_BACKEND_DRIVERENUMS_H
    namespace backend {
        enum class Backend : uint8_t {
            DEFAULT = 0,
            OPENGL = 1,
            VULKAN = 2,
            METAL = 3,
            WEBGPU = 4,
            NOOP = 5,
        };
    } // namespace backend
#endif

    namespace gltfio {
        class MaterialProvider;
        class AssetLoader;
        class ResourceLoader;
        class TextureProvider;
        class FilamentAsset;
    } // namespace gltfio
} // namespace filament

namespace FilamentBridge {

    struct EngineConfig {
        uint32_t driverHandleArenaSizeMB = 0;
        uint32_t commandBufferSizeMB = 0;
        uint32_t perRenderPassArenaSizeMB = 0;
        uint32_t minCommandBufferSizeMB = 0;
        uint32_t perFrameCommandsSizeMB = 0;
    };

    filament::Engine* createEngine(
            filament::backend::Backend backend = filament::backend::Backend::DEFAULT,
            const EngineConfig* config = nullptr);
    void destroyEngine(filament::Engine* engine);

    filament::Renderer* createRenderer(filament::Engine* engine);
    void destroyRenderer(filament::Engine* engine, filament::Renderer* renderer);

    filament::Scene* createScene(filament::Engine* engine);
    void destroyScene(filament::Engine* engine, filament::Scene* scene);

    filament::View* createView(filament::Engine* engine);
    void destroyView(filament::Engine* engine, filament::View* view);

    filament::SwapChain* createSwapChain(filament::Engine* engine, void* nativeWindow, uint64_t flags = 0);
    filament::SwapChain* createHeadlessSwapChain(filament::Engine* engine, uint32_t width, uint32_t height, uint64_t flags = 0);
    uint64_t getSwapChainFlagTransparent();
    uint64_t getSwapChainFlagReadable();
    void destroySwapChain(filament::Engine* engine, filament::SwapChain* swapChain);

    utils::Entity createCamera(filament::Engine* engine);
    filament::Camera* getCamera(filament::Engine* engine, utils::Entity entity);
    void destroyCamera(filament::Engine* engine, utils::Entity entity);
    utils::Entity entityFromId(uint32_t entityId);

    //! Same as destroyCamera() but takes the raw entity id, so callers can pass
    //! Sendable values across actor boundaries during teardown.
    void destroyCameraById(filament::Engine* engine, uint32_t entityId);

    void setViewScene(filament::View* view, filament::Scene* scene);
    void setViewCamera(filament::View* view, filament::Camera* camera);

    void setCameraProjection(filament::Camera* camera, double fovInDegrees, double aspect, double nearPlane, double farPlane);
    void setCameraLookAt(filament::Camera* camera,
                         double eyeX, double eyeY, double eyeZ,
                         double centerX, double centerY, double centerZ,
                         double upX, double upY, double upZ);

    utils::Entity createDirectionalLight(filament::Engine* engine, filament::Scene* scene,
                                         float dirX, float dirY, float dirZ,
                                         float r, float g, float b, float intensity);
    void destroyLight(filament::Engine* engine, filament::Scene* scene, utils::Entity light);

    // Clients must only pass ids previously returned by createDirectionalLight() and not
    // yet destroyed; importing a stale or recycled id would corrupt unrelated entities.
    void destroyLightById(filament::Engine* engine, filament::Scene* scene, uint32_t lightId);

    void setViewBlendMode(filament::View* view, bool translucent);
    void setViewShadowingEnabled(filament::View* view, bool enabled);

    // ---------------------------------------------------------------------------
    // PBR / post-processing controls
    //
    // Enum values are passed as integers so Swift does not have to import the
    // (large) filament::Options translation units.
    // ---------------------------------------------------------------------------

    void setAntiAliasingMode(filament::View* view, uint32_t mode);
    void setMultiSampleCount(filament::View* view, uint32_t sampleCount);
    void setDitheringEnabled(filament::View* view, bool enabled);
    void setHDRQuality(filament::View* view, uint32_t quality);
    void setBloom(filament::View* view, bool enabled, float strength, uint32_t levels);
    void setVignette(filament::View* view, bool enabled, float strength,
                     float roundness, float feather, float midPoint);
    void setAmbientOcclusion(filament::View* view, bool enabled, uint32_t mode,
                             float intensity, float radius, float power);
    void setScreenSpaceReflections(filament::View* view, bool enabled, float maxDistance,
                                  float thickness, float stride);
    void setDepthOfField(filament::View* view, bool enabled, float cocScale, uint32_t ringCount);

    //! Applies a *multiplier* on Filament's default photographic exposure (f/16, 1/125s,
    //! ISO 100), so a multiplier of 1.0 leaves the scene exactly as Filament ships it.
    void setCameraExposureMultiplier(filament::Camera* camera, float multiplier);

    //! Builds a ColorGrading LUT. The caller owns the result and must dissociate it
    //! from every View (setViewColorGrading(view, nullptr)) before destroying it.
    filament::ColorGrading* createColorGrading(
            filament::Engine* engine,
            uint32_t toneMapping,
            float contrast,
            float saturation,
            float vibrance,
            float temperature,
            float tint);
    void setViewColorGrading(filament::View* view, filament::ColorGrading* colorGrading);
    void destroyColorGrading(filament::Engine* engine, filament::ColorGrading* colorGrading);
    size_t getColorGradingCount(filament::Engine* engine);

    // ---------------------------------------------------------------------------
    // Runtime light controls (no rebuild required)
    // ---------------------------------------------------------------------------

    void setLightIntensity(filament::Engine* engine, utils::Entity light, float intensity);
    void setLightColor(filament::Engine* engine, utils::Entity light, float r, float g, float b);
    void setLightDirection(filament::Engine* engine, utils::Entity light, float x, float y, float z);
    void setLightShadows(filament::Engine* engine, utils::Entity light, bool castShadows);

    void setViewport(filament::View* view, int32_t left, int32_t bottom, uint32_t width, uint32_t height);
    void setTransparent(filament::Renderer* renderer, bool transparent);
    void setClearColor(filament::Renderer* renderer, float r, float g, float b, float a);

    filament::IndirectLight* setAmbientLight(filament::Engine* engine, float intensity = 40000.0f);
    void setSceneAmbientLight(filament::Scene* scene, filament::IndirectLight* ibl);
    void destroyIndirectLight(filament::Engine* engine, filament::IndirectLight* ibl);
    size_t getIndirectLightCount(filament::Engine* engine);

    bool beginFrame(filament::Renderer* renderer, filament::SwapChain* swapChain);
    void renderView(filament::Renderer* renderer, filament::View* view);
    void endFrame(filament::Renderer* renderer);
    bool readPixels(filament::Engine* engine, filament::Renderer* renderer,
                    uint32_t x, uint32_t y, uint32_t width, uint32_t height,
                    void* outBuffer, size_t bufferSize);

    struct GlbContext {
        filament::gltfio::MaterialProvider* materials = nullptr;
        filament::gltfio::AssetLoader* loader = nullptr;
        filament::gltfio::ResourceLoader* resourceLoader = nullptr;
        filament::gltfio::TextureProvider* stbDecoder = nullptr;
        filament::gltfio::FilamentAsset* asset = nullptr;
    };

    GlbContext* loadGlbFromMemory(filament::Engine* engine, filament::Scene* scene, const uint8_t* data, size_t size);
    void setModelRotation(filament::Engine* engine, GlbContext* ctx, float radiansY);
    size_t getAnimationCount(GlbContext* ctx);
    const char* getAnimationName(GlbContext* ctx, size_t index);
    float getAnimationDuration(GlbContext* ctx, size_t index);
    void applyAnimation(GlbContext* ctx, size_t index, float timeInSeconds);
    void resetBoneMatrices(GlbContext* ctx);
    size_t getMorphTargetCount(GlbContext* ctx);
    const char* getMorphTargetName(GlbContext* ctx, size_t index);
    void setMorphWeight(filament::Engine* engine, GlbContext* ctx, size_t index, float weight);
    void setMorphWeightByName(filament::Engine* engine, GlbContext* ctx, const char* name, float weight);
    void applyMorphWeights(filament::Engine* engine, GlbContext* ctx, const float* weights, size_t count);
    void resetMorphWeights(filament::Engine* engine, GlbContext* ctx);
    void destroyGlbContext(filament::Engine* engine, filament::Scene* scene, GlbContext* ctx);
    void hideGlbAsset(filament::Scene* scene, GlbContext* ctx);
    void showGlbAsset(filament::Scene* scene, GlbContext* ctx);
    void setGlbPriority(filament::Engine* engine, GlbContext* ctx, uint8_t priority);

    // ---------------------------------------------------------------------------
    // Material & MaterialInstance lifecycle and controls
    // ---------------------------------------------------------------------------
    filament::Material* createMaterialFromPackage(filament::Engine* engine, const void* data, size_t size);
    void destroyMaterial(filament::Engine* engine, filament::Material* material);

    filament::MaterialInstance* createMaterialInstance(filament::Material* material);
    void destroyMaterialInstance(filament::Engine* engine, filament::MaterialInstance* instance);

    void setMaterialParameterInt(filament::MaterialInstance* inst, const char* name, int32_t v);
    void setMaterialParameterFloat(filament::MaterialInstance* inst, const char* name, float v);
    void setMaterialParameterFloat3(filament::MaterialInstance* inst, const char* name, float x, float y, float z);
    void setMaterialParameterFloat4(filament::MaterialInstance* inst, const char* name, float x, float y, float z, float w);

    void setMaterialOnRenderable(filament::Engine* engine, utils::Entity entity, filament::MaterialInstance* inst, size_t primitiveIndex = 0);
    void setMaterialOnAllPrimitives(filament::Engine* engine, utils::Entity entity, filament::MaterialInstance* inst);
    void applyMaterialToGlbAsset(filament::Engine* engine, GlbContext* ctx, filament::MaterialInstance* inst);

} // namespace FilamentBridge
