#pragma once

#include <filament/Engine.h>
#include <filament/Renderer.h>
#include <filament/Scene.h>
#include <filament/View.h>
#include <filament/Camera.h>
#include <filament/SwapChain.h>
#include <filament/Viewport.h>
#include <filament/Color.h>
#include <filament/LightManager.h>
#include <filament/IndirectLight.h>
#include <filament/TransformManager.h>
#include <filament/Box.h>
#include <filament/ColorGrading.h>
#include <filament/ToneMapper.h>

#include <gltfio/AssetLoader.h>
#include <gltfio/FilamentAsset.h>
#include <gltfio/FilamentInstance.h>
#include <gltfio/Animator.h>
#include <gltfio/ResourceLoader.h>
#include <gltfio/TextureProvider.h>
#include <gltfio/materials/uberarchive.h>

#include <math/mat4.h>
#include <math/quat.h>
#include <math/vec3.h>

#include <utils/EntityManager.h>
#include <utils/Entity.h>

namespace FilamentBridge {

    inline filament::Engine* createEngine(filament::backend::Backend backend = filament::backend::Backend::DEFAULT) {
        return filament::Engine::create(backend);
    }

    inline void destroyEngine(filament::Engine* engine) {
        filament::Engine::destroy(&engine);
    }

    inline filament::Renderer* createRenderer(filament::Engine* engine) {
        return engine->createRenderer();
    }

    inline void destroyRenderer(filament::Engine* engine, filament::Renderer* renderer) {
        engine->destroy(renderer);
    }

    inline filament::Scene* createScene(filament::Engine* engine) {
        return engine->createScene();
    }

    inline void destroyScene(filament::Engine* engine, filament::Scene* scene) {
        engine->destroy(scene);
    }

    inline filament::View* createView(filament::Engine* engine) {
        return engine->createView();
    }

    inline void destroyView(filament::Engine* engine, filament::View* view) {
        engine->destroy(view);
    }

    inline filament::SwapChain* createSwapChain(filament::Engine* engine, void* nativeWindow, uint64_t flags = 0) {
        return engine->createSwapChain(nativeWindow, flags);
    }

    inline uint64_t getSwapChainFlagTransparent() {
        return filament::SwapChain::CONFIG_TRANSPARENT;
    }

    inline void destroySwapChain(filament::Engine* engine, filament::SwapChain* swapChain) {
        engine->destroy(swapChain);
    }

    inline utils::Entity createCamera(filament::Engine* engine) {
        utils::Entity cameraEntity = utils::EntityManager::get().create();
        engine->createCamera(cameraEntity);
        return cameraEntity;
    }

    inline filament::Camera* getCamera(filament::Engine* engine, utils::Entity entity) {
        return engine->getCameraComponent(entity);
    }

    inline void destroyCamera(filament::Engine* engine, utils::Entity entity) {
        engine->destroyCameraComponent(entity);
        utils::EntityManager::get().destroy(entity);
    }

    inline utils::Entity entityFromId(uint32_t entityId) {
        return utils::Entity::import(static_cast<int32_t>(entityId));
    }

    //! Same as destroyCamera() but takes the raw entity id, so callers can pass
    //! Sendable values across actor boundaries during teardown.
    inline void destroyCameraById(filament::Engine* engine, uint32_t entityId) {
        destroyCamera(engine, entityFromId(entityId));
    }

    inline void setViewScene(filament::View* view, filament::Scene* scene) {
        view->setScene(scene);
    }

    inline void setViewCamera(filament::View* view, filament::Camera* camera) {
        view->setCamera(camera);
    }

    inline void setCameraProjection(filament::Camera* camera, double fovInDegrees, double aspect, double near, double far) {
        camera->setProjection(fovInDegrees, aspect, near, far, filament::Camera::Fov::VERTICAL);
    }

    inline void setCameraLookAt(filament::Camera* camera,
                                double eyeX, double eyeY, double eyeZ,
                                double centerX, double centerY, double centerZ,
                                double upX, double upY, double upZ) {
        camera->lookAt(
            filament::math::double3(eyeX, eyeY, eyeZ),
            filament::math::double3(centerX, centerY, centerZ),
            filament::math::double3(upX, upY, upZ)
        );
    }

    inline utils::Entity createDirectionalLight(filament::Engine* engine, filament::Scene* scene,
                                                 float dirX, float dirY, float dirZ,
                                                 float r, float g, float b, float intensity) {
        utils::Entity light = utils::EntityManager::get().create();
        filament::LightManager::Builder(filament::LightManager::Type::DIRECTIONAL)
            .color(filament::math::float3(r, g, b))
            .intensity(intensity)
            .direction(filament::math::float3(dirX, dirY, dirZ))
            .castShadows(true)
            .build(*engine, light);
        scene->addEntity(light);
        return light;
    }

    inline void destroyLight(filament::Engine* engine, filament::Scene* scene, utils::Entity light) {
        scene->remove(light);
        engine->getLightManager().destroy(light);
        utils::EntityManager::get().destroy(light);
    }

    // Clients must only pass ids previously returned by createDirectionalLight() and not
    // yet destroyed; importing a stale or recycled id would corrupt unrelated entities.
    inline void destroyLightById(filament::Engine* engine, filament::Scene* scene, uint32_t lightId) {
        utils::Entity light = utils::Entity::import(static_cast<int32_t>(lightId));
        destroyLight(engine, scene, light);
    }

    inline void setViewBlendMode(filament::View* view, bool translucent) {
        view->setBlendMode(translucent ? filament::View::BlendMode::TRANSLUCENT : filament::View::BlendMode::OPAQUE);
    }

    inline void setViewShadowingEnabled(filament::View* view, bool enabled) {
        view->setShadowingEnabled(enabled);
    }

    // ---------------------------------------------------------------------------
    // PBR / post-processing controls
    //
    // Enum values are passed as integers so Swift does not have to import the
    // (large) filament::Options translation units.
    // ---------------------------------------------------------------------------

    inline void setAntiAliasingMode(filament::View* view, uint32_t mode) {
        view->setAntiAliasing(mode ? filament::AntiAliasing::FXAA : filament::AntiAliasing::NONE);
    }

    inline void setMultiSampleCount(filament::View* view, uint32_t sampleCount) {
        view->setSampleCount(static_cast<uint8_t>(sampleCount));
    }

    inline void setDitheringEnabled(filament::View* view, bool enabled) {
        view->setDithering(enabled ? filament::Dithering::TEMPORAL : filament::Dithering::NONE);
    }

    inline void setHDRQuality(filament::View* view, uint32_t quality) {
        filament::RenderQuality rq;
        switch (quality) {
            case 0:  rq.hdrColorBuffer = filament::QualityLevel::LOW;    break;
            case 1:  rq.hdrColorBuffer = filament::QualityLevel::MEDIUM; break;
            case 2:  rq.hdrColorBuffer = filament::QualityLevel::HIGH;   break;
            default: rq.hdrColorBuffer = filament::QualityLevel::ULTRA;  break;
        }
        view->setRenderQuality(rq);
    }

    inline void setBloom(filament::View* view, bool enabled, float strength, uint32_t levels) {
        filament::BloomOptions options = view->getBloomOptions();
        options.enabled = enabled;
        options.strength = strength;
        options.levels = static_cast<uint8_t>(levels < 1 ? 1 : (levels > 11 ? 11 : levels));
        view->setBloomOptions(options);
    }

    inline void setVignette(filament::View* view, bool enabled, float strength,
                            float roundness, float feather, float midPoint) {
        filament::VignetteOptions options = view->getVignetteOptions();
        options.enabled = enabled;
        options.roundness = roundness;
        options.feather = feather;
        options.midPoint = midPoint;
        // VignetteOptions has no strength field: fold it into the vignette color.
        options.color = filament::math::float4(0.0f, 0.0f, 0.0f, strength);
        view->setVignetteOptions(options);
    }

    inline void setAmbientOcclusion(filament::View* view, bool enabled, uint32_t mode,
                                    float intensity, float radius, float power) {
        filament::AmbientOcclusionOptions options = view->getAmbientOcclusionOptions();
        options.enabled = enabled;
        options.aoType = mode ? filament::AmbientOcclusionOptions::AmbientOcclusionType::GTAO
                              : filament::AmbientOcclusionOptions::AmbientOcclusionType::SAO;
        options.intensity = intensity;
        options.radius = radius;
        options.power = power;
        view->setAmbientOcclusionOptions(options);
    }

    inline void setScreenSpaceReflections(filament::View* view, bool enabled, float maxDistance,
                                          float thickness, float stride) {
        filament::ScreenSpaceReflectionsOptions options = view->getScreenSpaceReflectionsOptions();
        options.enabled = enabled;
        options.maxDistance = maxDistance;
        options.thickness = thickness;
        options.stride = stride;
        view->setScreenSpaceReflectionsOptions(options);
    }

    inline void setDepthOfField(filament::View* view, bool enabled, float cocScale, uint32_t ringCount) {
        filament::DepthOfFieldOptions options = view->getDepthOfFieldOptions();
        const auto rings = static_cast<uint8_t>(ringCount < 3 ? 3 : (ringCount > 17 ? 17 : ringCount));
        options.enabled = enabled;
        options.cocScale = cocScale;
        options.foregroundRingCount = rings;
        options.backgroundRingCount = rings;
        options.fastGatherRingCount = rings;
        view->setDepthOfFieldOptions(options);
    }

    //! Applies a *multiplier* on Filament's default photographic exposure (f/16, 1/125s,
//! ISO 100), so a multiplier of 1.0 leaves the scene exactly as Filament ships it.
//!
//! Note this deliberately does NOT call Camera::setExposure(float), which hardcodes
//! f/1.0 and a 1.2s shutter and is therefore ~100x brighter than the default.
inline void setCameraExposureMultiplier(filament::Camera* camera, float multiplier) {
    const float clamped = multiplier < 0.01f ? 0.01f : (multiplier > 1000.0f ? 1000.0f : multiplier);
    // Scene exposure scales with (sensitivity / 100) / (aperture^2 * shutterSpeed), so
    // scaling the shutter speed scales the brightness linearly.
    camera->setExposure(16.0f, (1.0f / 125.0f) * clamped, 100.0f);
    }

    //! Builds a ColorGrading LUT. The caller owns the result and must dissociate it
    //! from every View (setViewColorGrading(view, nullptr)) before destroying it.
    inline filament::ColorGrading* createColorGrading(
            filament::Engine* engine,
            uint32_t toneMapping,
            float contrast,
            float saturation,
            float vibrance,
            float temperature,
            float tint) {
        // Function-local statics: taking the address of a temporary would dangle by the
        // time ColorGrading::Builder::build() runs.
        static const filament::LinearToneMapper sLinear;
        static const filament::ACESLegacyToneMapper sAcesLegacy;
        static const filament::ACESToneMapper sAces;
        static const filament::FilmicToneMapper sFilmic;
        static const filament::PBRNeutralToneMapper sPBRNeutral;
        static const filament::AgxToneMapper sAgx;
        static const filament::GT7ToneMapper sGT7;

        const filament::ToneMapper* toneMapper = &sAces;
        switch (toneMapping) {
            case 0:  toneMapper = &sLinear;      break;
            case 1:  toneMapper = &sAcesLegacy; break;
            case 2:  toneMapper = &sAces;       break;
            case 3:  toneMapper = &sFilmic;     break;
            case 4:  toneMapper = &sPBRNeutral; break;
            case 5:  toneMapper = &sAgx;        break;
            case 6:  toneMapper = &sGT7;        break;
            default: break;
        }

        return filament::ColorGrading::Builder()
                .toneMapper(toneMapper)
                .contrast(contrast)
                .saturation(saturation)
                .vibrance(vibrance)
                .whiteBalance(temperature, tint)
                .build(*engine);
    }

    inline void setViewColorGrading(filament::View* view, filament::ColorGrading* colorGrading) {
        view->setColorGrading(colorGrading);
    }

    inline void destroyColorGrading(filament::Engine* engine, filament::ColorGrading* colorGrading) {
        if (!colorGrading) return;
        engine->destroy(colorGrading);
    }

    inline size_t getColorGradingCount(filament::Engine* engine) {
        return engine->getColorGradingCount();
    }

    // ---------------------------------------------------------------------------
    // Runtime light controls (no rebuild required)
    // ---------------------------------------------------------------------------

    inline void setLightIntensity(filament::Engine* engine, utils::Entity light, float intensity) {
        engine->getLightManager().setIntensity(engine->getLightManager().getInstance(light), intensity);
    }

    inline void setLightColor(filament::Engine* engine, utils::Entity light, float r, float g, float b) {
        engine->getLightManager().setColor(
                engine->getLightManager().getInstance(light), filament::math::float3(r, g, b));
    }

    inline void setLightDirection(filament::Engine* engine, utils::Entity light, float x, float y, float z) {
        engine->getLightManager().setDirection(
                engine->getLightManager().getInstance(light), filament::math::float3(x, y, z));
    }

    inline void setLightShadows(filament::Engine* engine, utils::Entity light, bool castShadows) {
        engine->getLightManager().setShadowCaster(
                engine->getLightManager().getInstance(light), castShadows);
    }

    inline void setViewport(filament::View* view, int32_t left, int32_t bottom, uint32_t width, uint32_t height) {
        view->setViewport(filament::Viewport(left, bottom, width, height));
    }

    inline void setTransparent(filament::Renderer* renderer, bool transparent) {
        filament::Renderer::ClearOptions clearOptions = renderer->getClearOptions();
        clearOptions.clear = true;
        if (transparent) {
            clearOptions.clearColor = filament::math::float4(0.0f, 0.0f, 0.0f, 0.0f);
        } else {
            clearOptions.clearColor = filament::math::float4(0.12f, 0.13f, 0.16f, 1.0f);
        }
        renderer->setClearOptions(clearOptions);
    }

    inline void setClearColor(filament::Renderer* renderer, float r, float g, float b, float a) {
        filament::Renderer::ClearOptions clearOptions = renderer->getClearOptions();
        clearOptions.clear = true;
        clearOptions.clearColor = filament::math::float4(r, g, b, a);
        renderer->setClearOptions(clearOptions);
    }

    inline filament::IndirectLight* setAmbientLight(filament::Engine* engine, float intensity = 40000.0f) {
        filament::math::float3 sh[1] = { filament::math::float3(1.0f, 1.0f, 1.0f) };
        return filament::IndirectLight::Builder()
            .irradiance(1, sh)
            .intensity(intensity)
            .build(*engine);
    }

    inline void setSceneAmbientLight(filament::Scene* scene, filament::IndirectLight* ibl) {
        scene->setIndirectLight(ibl);
    }

    inline void destroyIndirectLight(filament::Engine* engine, filament::IndirectLight* ibl) {
        if (!ibl) return;
        engine->destroy(ibl);
    }

    //! Number of live IndirectLight objects owned by the engine (diagnostics/tests).
    inline size_t getIndirectLightCount(filament::Engine* engine) {
        return engine->getIndirectLightCount();
    }

    inline bool beginFrame(filament::Renderer* renderer, filament::SwapChain* swapChain) {
        return renderer->beginFrame(swapChain);
    }

    inline void renderView(filament::Renderer* renderer, filament::View* view) {
        renderer->render(view);
    }

    inline void endFrame(filament::Renderer* renderer) {
        renderer->endFrame();
    }

    struct GlbContext {
        filament::gltfio::MaterialProvider* materials = nullptr;
        filament::gltfio::AssetLoader* loader = nullptr;
        filament::gltfio::ResourceLoader* resourceLoader = nullptr;
        filament::gltfio::TextureProvider* stbDecoder = nullptr;
        filament::gltfio::FilamentAsset* asset = nullptr;
    };

    inline GlbContext* loadGlbFromMemory(filament::Engine* engine, filament::Scene* scene, const uint8_t* data, size_t size) {
        if (!engine || !scene || !data || size == 0) return nullptr;

        auto* ctx = new GlbContext();
        ctx->materials = filament::gltfio::createUbershaderProvider(engine, UBERARCHIVE_DEFAULT_DATA, UBERARCHIVE_DEFAULT_SIZE);
        ctx->loader = filament::gltfio::AssetLoader::create({engine, ctx->materials});
        ctx->asset = ctx->loader->createAsset(data, static_cast<uint32_t>(size));

        if (!ctx->asset) {
            if (ctx->materials) {
                ctx->materials->destroyMaterials();
                delete ctx->materials;
            }
            filament::gltfio::AssetLoader::destroy(&ctx->loader);
            delete ctx;
            return nullptr;
        }

        filament::gltfio::ResourceConfiguration resourceConfig = {};
        resourceConfig.engine = engine;
        resourceConfig.normalizeSkinningWeights = true;
        ctx->resourceLoader = new filament::gltfio::ResourceLoader(resourceConfig);

        ctx->stbDecoder = filament::gltfio::createStbProvider(engine);
        if (ctx->stbDecoder) {
            ctx->resourceLoader->addTextureProvider("image/png", ctx->stbDecoder);
            ctx->resourceLoader->addTextureProvider("image/jpeg", ctx->stbDecoder);
        }

        ctx->resourceLoader->loadResources(ctx->asset);
        ctx->asset->releaseSourceData();

        scene->addEntities(ctx->asset->getEntities(), ctx->asset->getEntityCount());
        return ctx;
    }

    inline void setModelRotation(filament::Engine* engine, GlbContext* ctx, float radiansY) {
        if (!engine || !ctx || !ctx->asset) return;
        auto& tm = engine->getTransformManager();
        auto root = ctx->asset->getRoot();
        auto inst = tm.getInstance(root);
        if (!inst.isValid()) return;

        auto aabb = ctx->asset->getBoundingBox();
        auto center = aabb.center();
        auto halfExtent = aabb.extent();
        float maxDim = std::max({halfExtent.x, halfExtent.y, halfExtent.z}) * 2.0f;
        float scale = (maxDim > 0.0001f) ? (2.0f / maxDim) : 1.0f;

        filament::math::mat4f rot(filament::math::quatf::fromAxisAngle(filament::math::float3(0, 1, 0), radiansY));
        filament::math::mat4f transform = rot *
                                          filament::math::mat4f::scaling(scale) *
                                          filament::math::mat4f::translation(-center);
        tm.setTransform(inst, transform);
    }

    inline size_t getAnimationCount(GlbContext* ctx) {
        if (!ctx || !ctx->asset) return 0;
        auto* inst = ctx->asset->getInstance();
        if (!inst) return 0;
        auto* animator = inst->getAnimator();
        return animator ? animator->getAnimationCount() : 0;
    }

    inline const char* getAnimationName(GlbContext* ctx, size_t index) {
        if (!ctx || !ctx->asset) return "";
        auto* inst = ctx->asset->getInstance();
        if (!inst) return "";
        auto* animator = inst->getAnimator();
        if (!animator || index >= animator->getAnimationCount()) return "";
        const char* name = animator->getAnimationName(index);
        return name ? name : "";
    }

    inline float getAnimationDuration(GlbContext* ctx, size_t index) {
        if (!ctx || !ctx->asset) return 0.0f;
        auto* inst = ctx->asset->getInstance();
        if (!inst) return 0.0f;
        auto* animator = inst->getAnimator();
        if (!animator || index >= animator->getAnimationCount()) return 0.0f;
        return animator->getAnimationDuration(index);
    }

    inline void applyAnimation(GlbContext* ctx, size_t index, float timeInSeconds) {
        if (!ctx || !ctx->asset) return;
        auto* inst = ctx->asset->getInstance();
        if (!inst) return;
        auto* animator = inst->getAnimator();
        if (!animator) return;
        animator->applyAnimation(index, timeInSeconds);
        animator->updateBoneMatrices();
    }

    inline void resetBoneMatrices(GlbContext* ctx) {
        if (!ctx || !ctx->asset) return;
        auto* inst = ctx->asset->getInstance();
        if (!inst) return;
        auto* animator = inst->getAnimator();
        if (!animator) return;
        animator->resetBoneMatrices();
    }

    inline void destroyGlbContext(filament::Engine* engine, filament::Scene* scene, GlbContext* ctx) {
        if (!ctx) return;

        // Teardown must follow the order documented by AssetLoader: detach from the scene,
        // destroy the asset first, then destroy the providers that backed its GPU resources.
        // destroyMaterials() must be called or the cached materials leak.
        if (scene && ctx->asset) {
            scene->removeEntities(ctx->asset->getEntities(), ctx->asset->getEntityCount());
        }

        if (ctx->loader && ctx->asset) {
            ctx->loader->destroyAsset(ctx->asset);
        }
        ctx->asset = nullptr;

        if (ctx->resourceLoader) {
            delete ctx->resourceLoader;
            ctx->resourceLoader = nullptr;
        }
        if (ctx->stbDecoder) {
            delete ctx->stbDecoder;
            ctx->stbDecoder = nullptr;
        }
        if (ctx->materials) {
            ctx->materials->destroyMaterials();
            delete ctx->materials;
            ctx->materials = nullptr;
        }
        if (ctx->loader) {
            filament::gltfio::AssetLoader::destroy(&ctx->loader);
        }

        delete ctx;
    }

} // namespace FilamentBridge
