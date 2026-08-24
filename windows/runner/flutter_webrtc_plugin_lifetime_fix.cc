#include "flutter_webrtc/flutter_web_r_t_c_plugin.h"

#include "flutter_common.h"
#include "flutter_webrtc.h"
#include "task_runner_windows.h"

#include <flutter/plugin_registrar_windows.h>

const char* kChannelName = "FlutterWebRTC.Method";
static flutter_webrtc_plugin::FlutterWebRTC* g_shared_instance = nullptr;

namespace flutter_webrtc_plugin {

class FlutterWebRTCPluginImpl;
static FlutterWebRTCPluginImpl* g_plugin_instance = nullptr;

// Local replacement for flutter_webrtc 1.6.0's Windows plugin entrypoint.
//
// The upstream class declares task_runner_ after webrtc_. C++ destroys members
// in reverse declaration order, so the task runner disappears while WebRTC
// objects and callbacks can still reference it. It also lets the Flutter engine
// begin destroying its registrar before the plugin's event channel is released;
// that channel then tries to unregister itself through a dead messenger.
class FlutterWebRTCPluginImpl : public FlutterWebRTCPlugin {
 public:
  static void RegisterWithRegistrar(PluginRegistrar* registrar) {
    auto channel = std::make_unique<MethodChannel>(
        registrar->messenger(), kChannelName,
        &flutter::StandardMethodCodec::GetInstance());

    auto* channel_pointer = channel.get();
    std::unique_ptr<FlutterWebRTCPluginImpl> plugin(
        new FlutterWebRTCPluginImpl(registrar, std::move(channel)));
    channel_pointer->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto& call, auto result) {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    g_plugin_instance = plugin.get();
    registrar->AddPlugin(std::move(plugin));
  }

  ~FlutterWebRTCPluginImpl() override {
    PrepareForShutdown();
    g_plugin_instance = nullptr;
  }

  void PrepareForShutdown() {
    if (!webrtc_) {
      return;
    }

    // This is called by FlutterWindow while the engine and its messenger are
    // still valid. FlutterWebRTC's event-channel destructor unregisters a
    // handler through that messenger, so it must run before controller teardown.
    channel_->SetMethodCallHandler(nullptr);
    g_shared_instance = nullptr;
    webrtc_.reset();
  }

  BinaryMessenger* messenger() { return messenger_; }

  TextureRegistrar* textures() { return textures_; }

  TaskRunner* task_runner() { return task_runner_.get(); }

 private:
  FlutterWebRTCPluginImpl(PluginRegistrar* registrar,
                          std::unique_ptr<MethodChannel> channel)
      : channel_(std::move(channel)),
        messenger_(registrar->messenger()),
        textures_(registrar->texture_registrar()),
        task_runner_(std::make_unique<TaskRunnerWindows>()) {
    webrtc_ = std::make_unique<FlutterWebRTC>(this);
    g_shared_instance = webrtc_.get();
  }

  void HandleMethodCall(const MethodCall& method_call,
                        std::unique_ptr<MethodResult> result) {
    auto method_call_proxy = MethodCallProxy::Create(method_call);
    webrtc_->HandleMethodCall(*method_call_proxy,
                              MethodResultProxy::Create(std::move(result)));
  }

  std::unique_ptr<MethodChannel> channel_;
  std::unique_ptr<FlutterWebRTC> webrtc_;
  BinaryMessenger* messenger_;
  TextureRegistrar* textures_;
  std::unique_ptr<TaskRunner> task_runner_;
};

}  // namespace flutter_webrtc_plugin

void FlutterWebRTCPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_webrtc_plugin::FlutterWebRTCPluginImpl::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

flutter_webrtc_plugin::FlutterWebRTC* FlutterWebRTCPluginSharedInstance() {
  return g_shared_instance;
}

extern "C" __declspec(dllexport) void
FlutterWebRTCPluginPrepareForShutdown() {
  if (flutter_webrtc_plugin::g_plugin_instance) {
    flutter_webrtc_plugin::g_plugin_instance->PrepareForShutdown();
  }
}
