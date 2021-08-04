
// Edge/Chromium headers and libs
#include <WebView2.h>
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")

//
// Edge/Chromium browser engine
//
class edge_chromium : public browser
{
public:
  bool embed(HWND wnd, bool debug, msg_cb_t cb) override
  {
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    std::atomic_flag flag = ATOMIC_FLAG_INIT;
    flag.test_and_set();

    wchar_t currentExePath[MAX_PATH];
    GetModuleFileNameW(NULL, currentExePath, MAX_PATH);
    // char *currentExeName = PathFindFileNameA(currentExePath);

    wchar_t userDataFolderBit[MAX_PATH];
    GetEnvironmentVariableW(L"APPDATA", userDataFolderBit, MAX_PATH);

    wchar_t folder[MAX_PATH];
    wcscpy(folder, userDataFolderBit);
    wcscat(folder, L"/");
    wcscat(folder, L"ZigWebViewDemo");

    wprintf(L"folder = %ls\n", folder);

    auto handler = new webview2_com_handler(wnd, cb,
                                            [&](ICoreWebView2Controller *controller)
                                            {
                                              printf("ready %p\n", controller);
                                              m_controller = controller;
                                              if (m_controller != nullptr)
                                              {
                                                m_controller->get_CoreWebView2(&m_webview);
                                                m_webview->AddRef();
                                              }
                                              flag.clear();
                                            });
    HRESULT res = CreateCoreWebView2EnvironmentWithOptions(
        nullptr, folder, nullptr, handler);
    if (res != S_OK)
    {
      CoUninitialize();
      if (res == HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND))
      {
        printf("File not found?\n");
      }
      printf("failed to create webview: 0x%X!\n", res);
      return false;
    }
    MSG msg = {};
    while (flag.test_and_set() && GetMessage(&msg, NULL, 0, 0))
    {
      TranslateMessage(&msg);
      DispatchMessage(&msg);
    }
    if (this->m_controller == nullptr)
      return false;
    init("window.external={invoke:s=>window.chrome.webview.postMessage(s)}");
    return true;
  }

  void resize(HWND wnd) override
  {
    RECT bounds;
    GetClientRect(wnd, &bounds);
    m_controller->put_IsVisible(true);
    m_controller->put_ParentWindow(wnd);
    m_controller->put_Bounds(bounds);
  }

  void navigate(const std::string url) override
  {
    auto wurl = to_lpwstr(url);
    m_webview->Navigate(wurl);
    delete[] wurl;
  }

  void init(const std::string js) override
  {
    LPCWSTR wjs = to_lpwstr(js);
    m_webview->AddScriptToExecuteOnDocumentCreated(wjs, nullptr);
    delete[] wjs;
  }

  void eval(const std::string js) override
  {
    LPCWSTR wjs = to_lpwstr(js);
    m_webview->ExecuteScript(wjs, nullptr);
    delete[] wjs;
  }

private:
  LPWSTR to_lpwstr(const std::string s)
  {
    int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, NULL, 0);
    wchar_t *ws = new wchar_t[n];
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, ws, n);
    return ws;
  }

  ICoreWebView2 *m_webview = nullptr;
  ICoreWebView2Controller *m_controller = nullptr;

  class webview2_com_handler
      : public ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler,
        public ICoreWebView2CreateCoreWebView2ControllerCompletedHandler,
        public ICoreWebView2WebMessageReceivedEventHandler,
        public ICoreWebView2PermissionRequestedEventHandler
  {
    using webview2_com_handler_cb_t =
        std::function<void(ICoreWebView2Controller *)>;

  public:
    webview2_com_handler(HWND hwnd, msg_cb_t msgCb,
                         webview2_com_handler_cb_t cb)
        : m_window(hwnd), m_msgCb(msgCb), m_cb(cb) {}
    ULONG STDMETHODCALLTYPE AddRef() { return 1; }
    ULONG STDMETHODCALLTYPE Release() { return 1; }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, LPVOID *ppv)
    {
      return S_OK;
    }
    HRESULT STDMETHODCALLTYPE Invoke(HRESULT res,
                                     ICoreWebView2Environment *env)
    {
      printf("created env: 0x%X, env=%p, hwnd=%p\n", res, env, m_window);
      env->CreateCoreWebView2Controller(m_window, this);
      return S_OK;
    }
    HRESULT STDMETHODCALLTYPE Invoke(HRESULT res,
                                     ICoreWebView2Controller *controller)
    {
      printf("hresult: 0x%X, controller=%p\n", res, controller);
      if (controller != nullptr)
      {
        controller->AddRef();

        ICoreWebView2 *webview;
        ::EventRegistrationToken token;
        controller->get_CoreWebView2(&webview);
        webview->add_WebMessageReceived(this, &token);
        webview->add_PermissionRequested(this, &token);

        ICoreWebView2Settings *Settings;
        webview->get_Settings(&Settings);
        Settings->put_IsScriptEnabled(TRUE);
        Settings->put_AreDefaultScriptDialogsEnabled(TRUE);
        Settings->put_IsWebMessageEnabled(TRUE);
      }
      m_cb(controller);
      return S_OK;
    }
    HRESULT STDMETHODCALLTYPE Invoke(
        ICoreWebView2 *sender, ICoreWebView2WebMessageReceivedEventArgs *args)
    {
      LPWSTR message;
      args->TryGetWebMessageAsString(&message);

      char long_buffer[4096];
      sprintf_s(long_buffer, sizeof long_buffer, "%ls", message);

      m_msgCb(long_buffer);

      sender->PostWebMessageAsString(message);

      CoTaskMemFree(message);
      return S_OK;
    }
    HRESULT STDMETHODCALLTYPE
    Invoke(ICoreWebView2 *sender,
           ICoreWebView2PermissionRequestedEventArgs *args)
    {
      COREWEBVIEW2_PERMISSION_KIND kind;
      args->get_PermissionKind(&kind);
      if (kind == COREWEBVIEW2_PERMISSION_KIND_CLIPBOARD_READ)
      {
        args->put_State(COREWEBVIEW2_PERMISSION_STATE_ALLOW);
      }
      return S_OK;
    }

  private:
    HWND m_window;
    msg_cb_t m_msgCb;
    webview2_com_handler_cb_t m_cb;
  };
};