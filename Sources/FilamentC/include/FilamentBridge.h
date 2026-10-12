#pragma once

#include <filament/Engine.h>
#include <filament/Renderer.h>
#include <filament/Scene.h>
#include <filament/View.h>
#include <filament/Camera.h>
#include <filament/SwapChain.h>
#include <filament/Viewport.h>
#include <filament/Color.h>

#include <gltfio/AssetLoader.h>
#include <gltfio/FilamentAsset.h>
#include <gltfio/ResourceLoader.h>
#include <gltfio/materials/uberarchive.h>

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

    inline filament::SwapChain* createSwapChain(filament::Engine* engine, void* nativeWindow) {
        return engine->createSwapChain(nativeWindow);
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

    inline void setViewScene(filament::View* view, filament::Scene* scene) {
        view->setScene(scene);
    }

    inline void setViewCamera(filament::View* view, filament::Camera* camera) {
        view->setCamera(camera);
    }

    inline void setViewBlendMode(filament::View* view, bool translucent) {
        view->setBlendMode(translucent ? filament::View::BlendMode::TRANSLUCENT : filament::View::BlendMode::OPAQUE);
    }

    inline void setViewShadowingEnabled(filament::View* view, bool enabled) {
        view->setShadowingEnabled(enabled);
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
            clearOptions.clearColor = filament::math::float4(0.1f, 0.1f, 0.12f, 1.0f);
        }
        renderer->setClearOptions(clearOptions);
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

} // namespace FilamentBridge
