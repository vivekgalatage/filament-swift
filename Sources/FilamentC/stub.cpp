#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#undef min
#undef max
#undef near
#undef far
#endif

#include "FilamentC.h"

#include <filament/Box.h>
#include <filament/ColorGrading.h>
#include <filament/ToneMapper.h>

#include <gltfio/FilamentInstance.h>
#include <gltfio/TextureProvider.h>

#include <filament/Fence.h>
#include <filament/RenderableManager.h>
#include <backend/PixelBufferDescriptor.h>

#include <algorithm>
#include <cstring>
#include <vector>

#include "FilamentBridge.h"

namespace FilamentBridge {

    filament::Engine* createEngine(filament::backend::Backend backend, const EngineConfig* config) {
        if (!config) {
            return filament::Engine::create(backend);
        }
        filament::Engine::Config engineConfig;
        if (config->driverHandleArenaSizeMB > 0) {
            engineConfig.driverHandleArenaSizeMB = config->driverHandleArenaSizeMB;
        }
        if (config->commandBufferSizeMB > 0) {
            engineConfig.commandBufferSizeMB = config->commandBufferSizeMB;
        }
        if (config->perRenderPassArenaSizeMB > 0) {
            engineConfig.perRenderPassArenaSizeMB = config->perRenderPassArenaSizeMB;
        }
        if (config->minCommandBufferSizeMB > 0) {
            engineConfig.minCommandBufferSizeMB = config->minCommandBufferSizeMB;
        }
        if (config->perFrameCommandsSizeMB > 0) {
            engineConfig.perFrameCommandsSizeMB = config->perFrameCommandsSizeMB;
        }
        return filament::Engine::Builder()
            .backend(backend)
            .config(&engineConfig)
            .build();
    }

    void destroyEngine(filament::Engine* engine) {
        filament::Engine::destroy(&engine);
    }

    filament::Renderer* createRenderer(filament::Engine* engine) {
        return engine->createRenderer();
    }

    void destroyRenderer(filament::Engine* engine, filament::Renderer* renderer) {
        engine->destroy(renderer);
    }

    filament::Scene* createScene(filament::Engine* engine) {
        return engine->createScene();
    }

    void destroyScene(filament::Engine* engine, filament::Scene* scene) {
        engine->destroy(scene);
    }

    filament::View* createView(filament::Engine* engine) {
        return engine->createView();
    }

    void destroyView(filament::Engine* engine, filament::View* view) {
        engine->destroy(view);
    }

    filament::SwapChain* createSwapChain(filament::Engine* engine, void* nativeWindow, uint64_t flags) {
        return engine->createSwapChain(nativeWindow, flags);
    }

    filament::SwapChain* createHeadlessSwapChain(filament::Engine* engine, uint32_t width, uint32_t height, uint64_t flags) {
        return engine->createSwapChain(width, height, flags);
    }

    uint64_t getSwapChainFlagTransparent() {
        return filament::SwapChain::CONFIG_TRANSPARENT;
    }

    uint64_t getSwapChainFlagReadable() {
        return filament::SwapChain::CONFIG_READABLE;
    }

    void destroySwapChain(filament::Engine* engine, filament::SwapChain* swapChain) {
        engine->destroy(swapChain);
    }

    utils::Entity createCamera(filament::Engine* engine) {
        utils::Entity cameraEntity = utils::EntityManager::get().create();
        engine->createCamera(cameraEntity);
        return cameraEntity;
    }

    filament::Camera* getCamera(filament::Engine* engine, utils::Entity entity) {
        return engine->getCameraComponent(entity);
    }

    void destroyCamera(filament::Engine* engine, utils::Entity entity) {
        engine->destroyCameraComponent(entity);
        utils::EntityManager::get().destroy(entity);
    }

    utils::Entity entityFromId(uint32_t entityId) {
        return utils::Entity::import(static_cast<int32_t>(entityId));
    }

    void destroyCameraById(filament::Engine* engine, uint32_t entityId) {
        destroyCamera(engine, entityFromId(entityId));
    }

    void setViewScene(filament::View* view, filament::Scene* scene) {
        view->setScene(scene);
    }

    void setViewCamera(filament::View* view, filament::Camera* camera) {
        view->setCamera(camera);
    }

    void setCameraProjection(filament::Camera* camera, double fovInDegrees, double aspect, double nearPlane, double farPlane) {
        camera->setProjection(fovInDegrees, aspect, nearPlane, farPlane, filament::Camera::Fov::VERTICAL);
    }

    void setCameraLookAt(filament::Camera* camera,
                         double eyeX, double eyeY, double eyeZ,
                         double centerX, double centerY, double centerZ,
                         double upX, double upY, double upZ) {
        camera->lookAt(
            filament::math::double3(eyeX, eyeY, eyeZ),
            filament::math::double3(centerX, centerY, centerZ),
            filament::math::double3(upX, upY, upZ)
        );
    }

    utils::Entity createDirectionalLight(filament::Engine* engine, filament::Scene* scene,
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

    void destroyLight(filament::Engine* engine, filament::Scene* scene, utils::Entity light) {
        scene->remove(light);
        engine->getLightManager().destroy(light);
        utils::EntityManager::get().destroy(light);
    }

    void destroyLightById(filament::Engine* engine, filament::Scene* scene, uint32_t lightId) {
        utils::Entity light = utils::Entity::import(static_cast<int32_t>(lightId));
        destroyLight(engine, scene, light);
    }

    void setViewBlendMode(filament::View* view, bool translucent) {
        view->setBlendMode(translucent ? filament::View::BlendMode::TRANSLUCENT : filament::View::BlendMode::OPAQUE);
    }

    void setViewShadowingEnabled(filament::View* view, bool enabled) {
        view->setShadowingEnabled(enabled);
    }

    void setAntiAliasingMode(filament::View* view, uint32_t mode) {
        view->setAntiAliasing(mode ? filament::AntiAliasing::FXAA : filament::AntiAliasing::NONE);
    }

    void setMultiSampleCount(filament::View* view, uint32_t sampleCount) {
        filament::MultiSampleAntiAliasingOptions options = view->getMultiSampleAntiAliasingOptions();
        options.enabled = sampleCount > 1;
        options.sampleCount = static_cast<uint8_t>(sampleCount < 1 ? 1 : sampleCount);
        view->setMultiSampleAntiAliasingOptions(options);
    }

    void setDitheringEnabled(filament::View* view, bool enabled) {
        view->setDithering(enabled ? filament::Dithering::TEMPORAL : filament::Dithering::NONE);
    }

    void setHDRQuality(filament::View* view, uint32_t quality) {
        filament::RenderQuality rq;
        switch (quality) {
            case 0:  rq.hdrColorBuffer = filament::QualityLevel::LOW;    break;
            case 1:  rq.hdrColorBuffer = filament::QualityLevel::MEDIUM; break;
            case 2:  rq.hdrColorBuffer = filament::QualityLevel::HIGH;   break;
            default: rq.hdrColorBuffer = filament::QualityLevel::ULTRA;  break;
        }
        view->setRenderQuality(rq);
    }

    void setBloom(filament::View* view, bool enabled, float strength, uint32_t levels) {
        filament::BloomOptions options = view->getBloomOptions();
        options.enabled = enabled;
        options.strength = strength;
        options.levels = static_cast<uint8_t>(levels < 1 ? 1 : (levels > 11 ? 11 : levels));
        view->setBloomOptions(options);
    }

    void setVignette(filament::View* view, bool enabled, float strength,
                     float roundness, float feather, float midPoint) {
        filament::VignetteOptions options = view->getVignetteOptions();
        options.enabled = enabled;
        options.roundness = roundness;
        options.feather = feather;
        options.midPoint = midPoint;
        options.color = filament::math::float4(0.0f, 0.0f, 0.0f, strength);
        view->setVignetteOptions(options);
    }

    void setAmbientOcclusion(filament::View* view, bool enabled, uint32_t mode,
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

    void setScreenSpaceReflections(filament::View* view, bool enabled, float maxDistance,
                                  float thickness, float stride) {
        filament::ScreenSpaceReflectionsOptions options = view->getScreenSpaceReflectionsOptions();
        options.enabled = enabled;
        options.maxDistance = maxDistance;
        options.thickness = thickness;
        options.stride = stride;
        view->setScreenSpaceReflectionsOptions(options);
    }

    void setDepthOfField(filament::View* view, bool enabled, float cocScale, uint32_t ringCount) {
        filament::DepthOfFieldOptions options = view->getDepthOfFieldOptions();
        const auto rings = static_cast<uint8_t>(ringCount < 3 ? 3 : (ringCount > 17 ? 17 : ringCount));
        options.enabled = enabled;
        options.cocScale = cocScale;
        options.foregroundRingCount = rings;
        options.backgroundRingCount = rings;
        options.fastGatherRingCount = rings;
        view->setDepthOfFieldOptions(options);
    }

    void setCameraExposureMultiplier(filament::Camera* camera, float multiplier) {
        const float clamped = multiplier < 0.01f ? 0.01f : (multiplier > 1000.0f ? 1000.0f : multiplier);
        camera->setExposure(16.0f, (1.0f / 125.0f) * clamped, 100.0f);
    }

    filament::ColorGrading* createColorGrading(
            filament::Engine* engine,
            uint32_t toneMapping,
            float contrast,
            float saturation,
            float vibrance,
            float temperature,
            float tint) {
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

    void setViewColorGrading(filament::View* view, filament::ColorGrading* colorGrading) {
        view->setColorGrading(colorGrading);
    }

    void destroyColorGrading(filament::Engine* engine, filament::ColorGrading* colorGrading) {
        if (!colorGrading) return;
        engine->destroy(colorGrading);
    }

    size_t getColorGradingCount(filament::Engine* engine) {
        return engine->getColorGradingCount();
    }

    void setLightIntensity(filament::Engine* engine, utils::Entity light, float intensity) {
        engine->getLightManager().setIntensity(engine->getLightManager().getInstance(light), intensity);
    }

    void setLightColor(filament::Engine* engine, utils::Entity light, float r, float g, float b) {
        engine->getLightManager().setColor(
                engine->getLightManager().getInstance(light), filament::math::float3(r, g, b));
    }

    void setLightDirection(filament::Engine* engine, utils::Entity light, float x, float y, float z) {
        engine->getLightManager().setDirection(
                engine->getLightManager().getInstance(light), filament::math::float3(x, y, z));
    }

    void setLightShadows(filament::Engine* engine, utils::Entity light, bool castShadows) {
        engine->getLightManager().setShadowCaster(
                engine->getLightManager().getInstance(light), castShadows);
    }

    void setViewport(filament::View* view, int32_t left, int32_t bottom, uint32_t width, uint32_t height) {
        view->setViewport(filament::Viewport(left, bottom, width, height));
    }

    void setTransparent(filament::Renderer* renderer, bool transparent) {
        filament::Renderer::ClearOptions clearOptions = renderer->getClearOptions();
        clearOptions.clear = true;
        if (transparent) {
            clearOptions.clearColor = filament::math::float4(0.0f, 0.0f, 0.0f, 0.0f);
        } else {
            clearOptions.clearColor = filament::math::float4(0.12f, 0.13f, 0.16f, 1.0f);
        }
        renderer->setClearOptions(clearOptions);
    }

    void setClearColor(filament::Renderer* renderer, float r, float g, float b, float a) {
        filament::Renderer::ClearOptions clearOptions = renderer->getClearOptions();
        clearOptions.clear = true;
        clearOptions.clearColor = filament::math::float4(r, g, b, a);
        renderer->setClearOptions(clearOptions);
    }

    filament::IndirectLight* setAmbientLight(filament::Engine* engine, float intensity) {
        filament::math::float3 sh[1] = { filament::math::float3(1.0f, 1.0f, 1.0f) };
        return filament::IndirectLight::Builder()
            .irradiance(1, sh)
            .intensity(intensity)
            .build(*engine);
    }

    void setSceneAmbientLight(filament::Scene* scene, filament::IndirectLight* ibl) {
        scene->setIndirectLight(ibl);
    }

    void destroyIndirectLight(filament::Engine* engine, filament::IndirectLight* ibl) {
        if (!ibl) return;
        engine->destroy(ibl);
    }

    size_t getIndirectLightCount(filament::Engine* engine) {
        return engine->getIndirectLightCount();
    }

    bool beginFrame(filament::Renderer* renderer, filament::SwapChain* swapChain) {
        return renderer->beginFrame(swapChain);
    }

    void renderView(filament::Renderer* renderer, filament::View* view) {
        renderer->render(view);
    }

    void endFrame(filament::Renderer* renderer) {
        renderer->endFrame();
    }

    bool readPixels(filament::Engine* engine, filament::Renderer* renderer,
                    uint32_t x, uint32_t y, uint32_t width, uint32_t height,
                    void* outBuffer, size_t bufferSize) {
        if (!engine || !renderer || !outBuffer) return false;
        size_t requiredSize = static_cast<size_t>(width) * height * 4;
        if (bufferSize < requiredSize) return false;

        filament::backend::PixelBufferDescriptor pbd(
            outBuffer, requiredSize,
            filament::backend::PixelDataFormat::RGBA,
            filament::backend::PixelDataType::UBYTE
        );
        renderer->readPixels(x, y, width, height, std::move(pbd));
        auto* fence = engine->createFence();
        if (fence) {
            filament::Fence::waitAndDestroy(fence, filament::Fence::Mode::FLUSH);
            return true;
        }
        return false;
    }

    GlbContext* loadGlbFromMemory(filament::Engine* engine, filament::Scene* scene, const uint8_t* data, size_t size) {
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

    void setModelRotation(filament::Engine* engine, GlbContext* ctx, float radiansY) {
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

    size_t getAnimationCount(GlbContext* ctx) {
        if (!ctx || !ctx->asset) return 0;
        auto* inst = ctx->asset->getInstance();
        if (!inst) return 0;
        auto* animator = inst->getAnimator();
        return animator ? animator->getAnimationCount() : 0;
    }

    const char* getAnimationName(GlbContext* ctx, size_t index) {
        if (!ctx || !ctx->asset) return "";
        auto* inst = ctx->asset->getInstance();
        if (!inst) return "";
        auto* animator = inst->getAnimator();
        if (!animator || index >= animator->getAnimationCount()) return "";
        const char* name = animator->getAnimationName(index);
        return name ? name : "";
    }

    float getAnimationDuration(GlbContext* ctx, size_t index) {
        if (!ctx || !ctx->asset) return 0.0f;
        auto* inst = ctx->asset->getInstance();
        if (!inst) return 0.0f;
        auto* animator = inst->getAnimator();
        if (!animator || index >= animator->getAnimationCount()) return 0.0f;
        return animator->getAnimationDuration(index);
    }

    void applyAnimation(GlbContext* ctx, size_t index, float timeInSeconds) {
        if (!ctx || !ctx->asset) return;
        auto* inst = ctx->asset->getInstance();
        if (!inst) return;
        auto* animator = inst->getAnimator();
        if (!animator) return;
        animator->applyAnimation(index, timeInSeconds);
        animator->updateBoneMatrices();
    }

    void resetBoneMatrices(GlbContext* ctx) {
        if (!ctx || !ctx->asset) return;
        auto* inst = ctx->asset->getInstance();
        if (!inst) return;
        auto* animator = inst->getAnimator();
        if (!animator) return;
        animator->resetBoneMatrices();
    }

    size_t getMorphTargetCount(GlbContext* ctx) {
        if (!ctx || !ctx->asset) return 0;
        size_t total = 0;
        const auto* entities = ctx->asset->getEntities();
        size_t count = ctx->asset->getEntityCount();
        for (size_t i = 0; i < count; ++i) {
            total += ctx->asset->getMorphTargetCountAt(entities[i]);
        }
        return total;
    }

    const char* getMorphTargetName(GlbContext* ctx, size_t index) {
        if (!ctx || !ctx->asset) return nullptr;
        size_t running = 0;
        const auto* entities = ctx->asset->getEntities();
        size_t count = ctx->asset->getEntityCount();
        for (size_t i = 0; i < count; ++i) {
            size_t entityTargets = ctx->asset->getMorphTargetCountAt(entities[i]);
            if (index < running + entityTargets) {
                return ctx->asset->getMorphTargetNameAt(entities[i], index - running);
            }
            running += entityTargets;
        }
        return nullptr;
    }

    void setMorphWeight(filament::Engine* engine, GlbContext* ctx, size_t index, float weight) {
        if (!engine || !ctx || !ctx->asset) return;
        auto& rcm = engine->getRenderableManager();
        size_t running = 0;
        const auto* entities = ctx->asset->getEntities();
        size_t count = ctx->asset->getEntityCount();
        for (size_t i = 0; i < count; ++i) {
            size_t entityTargets = ctx->asset->getMorphTargetCountAt(entities[i]);
            if (index < running + entityTargets) {
                auto inst = rcm.getInstance(entities[i]);
                if (inst) {
                    size_t targetIdx = index - running;
                    rcm.setMorphWeights(inst, &weight, 1, targetIdx);
                }
                return;
            }
            running += entityTargets;
        }
    }

    void setMorphWeightByName(filament::Engine* engine, GlbContext* ctx, const char* name, float weight) {
        if (!engine || !ctx || !ctx->asset || !name) return;
        auto& rcm = engine->getRenderableManager();
        const auto* entities = ctx->asset->getEntities();
        size_t count = ctx->asset->getEntityCount();
        for (size_t i = 0; i < count; ++i) {
            size_t entityTargets = ctx->asset->getMorphTargetCountAt(entities[i]);
            for (size_t t = 0; t < entityTargets; ++t) {
                const char* targetName = ctx->asset->getMorphTargetNameAt(entities[i], t);
                if (targetName && strcmp(targetName, name) == 0) {
                    auto inst = rcm.getInstance(entities[i]);
                    if (inst) {
                        rcm.setMorphWeights(inst, &weight, 1, t);
                    }
                }
            }
        }
    }

    void applyMorphWeights(filament::Engine* engine, GlbContext* ctx, const float* weights, size_t count) {
        if (!engine || !ctx || !ctx->asset || !weights || count == 0) return;
        auto& rcm = engine->getRenderableManager();
        size_t running = 0;
        const auto* entities = ctx->asset->getEntities();
        size_t entityCount = ctx->asset->getEntityCount();
        for (size_t i = 0; i < entityCount; ++i) {
            size_t entityTargets = ctx->asset->getMorphTargetCountAt(entities[i]);
            if (entityTargets > 0) {
                auto inst = rcm.getInstance(entities[i]);
                if (inst) {
                    size_t toCopy = std::min(entityTargets, (running < count) ? (count - running) : 0);
                    if (toCopy > 0) {
                        rcm.setMorphWeights(inst, weights + running, toCopy, 0);
                    }
                }
                running += entityTargets;
            }
        }
    }

    void resetMorphWeights(filament::Engine* engine, GlbContext* ctx) {
        if (!engine || !ctx || !ctx->asset) return;
        auto& rcm = engine->getRenderableManager();
        const auto* entities = ctx->asset->getEntities();
        size_t count = ctx->asset->getEntityCount();
        for (size_t i = 0; i < count; ++i) {
            auto inst = rcm.getInstance(entities[i]);
            if (inst) {
                size_t numTargets = rcm.getMorphTargetCount(inst);
                if (numTargets > 0) {
                    std::vector<float> zeros(numTargets, 0.0f);
                    rcm.setMorphWeights(inst, zeros.data(), numTargets, 0);
                }
            }
        }
    }

    void destroyGlbContext(filament::Engine* engine, filament::Scene* scene, GlbContext* ctx) {
        if (!ctx) return;

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

    void hideGlbAsset(filament::Scene* scene, GlbContext* ctx) {
        if (!scene || !ctx || !ctx->asset) return;
        scene->removeEntities(ctx->asset->getEntities(), ctx->asset->getEntityCount());
    }

    void showGlbAsset(filament::Scene* scene, GlbContext* ctx) {
        if (!scene || !ctx || !ctx->asset) return;
        scene->addEntities(ctx->asset->getEntities(), ctx->asset->getEntityCount());
    }

    void setGlbPriority(filament::Engine* engine, GlbContext* ctx, uint8_t priority) {
        if (!engine || !ctx || !ctx->asset) return;
        auto& rcm = engine->getRenderableManager();
        const auto* entities = ctx->asset->getEntities();
        size_t count = ctx->asset->getEntityCount();
        for (size_t i = 0; i < count; ++i) {
            auto instance = rcm.getInstance(entities[i]);
            if (instance) {
                rcm.setPriority(instance, priority);
            }
        }
    }

    filament::Material* createMaterialFromPackage(filament::Engine* engine, const void* data, size_t size) {
        if (!engine || !data || size == 0) return nullptr;
        return filament::Material::Builder()
            .package(data, size)
            .build(*engine);
    }

    void destroyMaterial(filament::Engine* engine, filament::Material* material) {
        if (engine && material) {
            engine->destroy(material);
        }
    }

    filament::MaterialInstance* createMaterialInstance(filament::Material* material) {
        return material ? material->createInstance() : nullptr;
    }

    void destroyMaterialInstance(filament::Engine* engine, filament::MaterialInstance* instance) {
        if (engine && instance) {
            engine->destroy(instance);
        }
    }

    void setMaterialParameterInt(filament::MaterialInstance* inst, const char* name, int32_t v) {
        if (inst && name) {
            inst->setParameter(name, v);
        }
    }

    void setMaterialParameterFloat(filament::MaterialInstance* inst, const char* name, float v) {
        if (inst && name) {
            inst->setParameter(name, v);
        }
    }

    void setMaterialParameterFloat3(filament::MaterialInstance* inst, const char* name, float x, float y, float z) {
        if (inst && name) {
            inst->setParameter(name, filament::math::float3(x, y, z));
        }
    }

    void setMaterialParameterFloat4(filament::MaterialInstance* inst, const char* name, float x, float y, float z, float w) {
        if (inst && name) {
            inst->setParameter(name, filament::math::float4(x, y, z, w));
        }
    }

    void setMaterialOnRenderable(filament::Engine* engine, utils::Entity entity, filament::MaterialInstance* inst, size_t primitiveIndex) {
        if (!engine || !inst) return;
        auto& rcm = engine->getRenderableManager();
        auto instance = rcm.getInstance(entity);
        if (instance && primitiveIndex < rcm.getPrimitiveCount(instance)) {
            rcm.setMaterialInstanceAt(instance, primitiveIndex, inst);
        }
    }

    void setMaterialOnAllPrimitives(filament::Engine* engine, utils::Entity entity, filament::MaterialInstance* inst) {
        if (!engine || !inst) return;
        auto& rcm = engine->getRenderableManager();
        auto instance = rcm.getInstance(entity);
        if (instance) {
            size_t count = rcm.getPrimitiveCount(instance);
            for (size_t i = 0; i < count; ++i) {
                rcm.setMaterialInstanceAt(instance, i, inst);
            }
        }
    }

    void applyMaterialToGlbAsset(filament::Engine* engine, GlbContext* ctx, filament::MaterialInstance* inst) {
        if (!engine || !ctx || !ctx->asset || !inst) return;
        auto& rcm = engine->getRenderableManager();
        const auto* entities = ctx->asset->getEntities();
        size_t count = ctx->asset->getEntityCount();
        for (size_t i = 0; i < count; ++i) {
            auto instance = rcm.getInstance(entities[i]);
            if (instance) {
                size_t primCount = rcm.getPrimitiveCount(instance);
                for (size_t p = 0; p < primCount; ++p) {
                    rcm.setMaterialInstanceAt(instance, p, inst);
                }
            }
        }
    }

} // namespace FilamentBridge
