#ifndef FLUTTER_INAPPWEBVIEW_PLUGIN_COM_APARTMENT_H_
#define FLUTTER_INAPPWEBVIEW_PLUGIN_COM_APARTMENT_H_

#include <objbase.h>

namespace flutter_inappwebview_plugin
{
  // WebView2 requires COM to remain initialized for the lifetime of its
  // asynchronous environment/controller creation. The Flutter runner normally
  // initializes its platform thread, but a platform-channel call can arrive on
  // another thread and another native plugin can accidentally unbalance the
  // runner's COM reference. Keep an independent reference for every thread that
  // actually creates WebView2 objects.
  class ThreadComApartment
  {
  public:
    ThreadComApartment()
      : result_(::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)),
      ownsInitialization_(SUCCEEDED(result_))
    {}

    ~ThreadComApartment()
    {
      if (ownsInitialization_) {
        ::CoUninitialize();
      }
    }

    ThreadComApartment(const ThreadComApartment&) = delete;
    ThreadComApartment& operator=(const ThreadComApartment&) = delete;

    HRESULT result() const { return result_; }

  private:
    const HRESULT result_;
    const bool ownsInitialization_;
  };

  inline HRESULT ensureThreadComApartment()
  {
    thread_local ThreadComApartment apartment;
    return apartment.result();
  }
}

#endif // FLUTTER_INAPPWEBVIEW_PLUGIN_COM_APARTMENT_H_
