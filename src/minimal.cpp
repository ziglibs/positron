
#define UNICODE
#define WIN32_LEAN_AND_MEAN
#include <Shlwapi.h>
#include <codecvt>
#include <stdlib.h>
#include <windows.h>
#include <WinUser.h>

#include <WebView2.h>

#include <functional>

extern "C" WINUSERAPI BOOL WINAPI SetProcessDpiAwarenessContext(
    _In_ DPI_AWARENESS_CONTEXT value);

using msg_cb_t = std::function<void(const std::string)>;

static LRESULT wndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    // auto w = (browser_engine *)GetWindowLongPtr(hwnd, GWLP_USERDATA);
    switch (msg)
    {
    case WM_SIZE:
        //if (w->m_browser)
        //    w->m_browser->resize(hwnd);
        break;
    case WM_CLOSE:
        DestroyWindow(hwnd);
        break;
    case WM_DESTROY:
        // w->terminate();
        break;
        //case WM_GETMINMAXINFO:
        //{
        //    auto lpmmi = (LPMINMAXINFO)lp;
        //    if (w == nullptr)
        //    {
        //        return 0;
        //    }
        //    if (w->m_maxsz.x > 0 && w->m_maxsz.y > 0)
        //    {
        //        lpmmi->ptMaxSize = w->m_maxsz;
        //        lpmmi->ptMaxTrackSize = w->m_maxsz;
        //    }
        //    if (w->m_minsz.x > 0 && w->m_minsz.y > 0)
        //    {
        //        lpmmi->ptMinTrackSize = w->m_minsz;
        //    }
        //}
        //break;
    default:
        return DefWindowProc(hwnd, msg, wp, lp);
    }
    return 0;
}

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

            webview->Navigate(L"https://ziglang.org");
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

int main()
{
    HINSTANCE hInstance = GetModuleHandle(nullptr);
    HICON icon = (HICON)LoadImage(
        hInstance, IDI_APPLICATION, IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
        GetSystemMetrics(SM_CYSMICON), LR_DEFAULTCOLOR);

    WNDCLASSEX wc;
    ZeroMemory(&wc, sizeof(WNDCLASSEX));
    wc.cbSize = sizeof(WNDCLASSEX);
    wc.hInstance = hInstance;
    wc.lpszClassName = L"webview";
    wc.hIcon = icon;
    wc.hIconSm = icon;
    wc.lpfnWndProc = wndProc;
    RegisterClassEx(&wc);
    HWND window = CreateWindowExW(0L, L"webview", L"Title", WS_OVERLAPPEDWINDOW, CW_USEDEFAULT,
                                  CW_USEDEFAULT, 640, 480, nullptr, nullptr,
                                  GetModuleHandle(nullptr), nullptr);
    // SetWindowLongPtr(m_window, GWLP_USERDATA, (LONG_PTR)this);

    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE);
    ShowWindow(window, SW_SHOW);
    UpdateWindow(window);
    SetFocus(window);

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

    ICoreWebView2Controller *m_controller = nullptr;
    ICoreWebView2 *m_webview = nullptr;

    auto handler = new webview2_com_handler(
        window, [](std::string s)
        { printf("cb(%s)\n", s.c_str()); },
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
    wchar_t const *root =
        //L"Z:\\Temp\\positron\\vendor\\Microsoft.WebView2.FixedVersionRuntime.91.0.864.71.x64";
        //L"Z:\\Temp\\positron\\vendor\\Microsoft.WebView2.FixedVersionRuntime.92.0.902.62.x64";
        //L"C:\\Program Files (x86)\\Microsoft\\Edge Dev\\Application\\93.0.961.10";
        nullptr;
    HRESULT res = CreateCoreWebView2EnvironmentWithOptions(
        root, folder, nullptr, handler);
    if (res != S_OK)
    {
        CoUninitialize();
        if (res == HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND))
        {
            printf("File not found?\n");
        }
        printf("failed to create webview: 0x%X!\n", res);
        return 1;
    }
    {
        MSG msg = {};
        while (flag.test_and_set() && GetMessage(&msg, NULL, 0, 0))
        {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
    }
    if (m_controller == nullptr)
        return 1;
    //     init("window.external={invoke:s=>window.chrome.webview.postMessage(s)}");

    printf("Navigate() => 0x%X\n", m_webview->Navigate(L"https://ziglang.org"));

    RECT bounds;
    GetClientRect(window, &bounds);
    m_controller->put_Bounds(bounds);

    m_controller->get_Bounds(&bounds);
    printf("%d %d %d %d\n", bounds.left, bounds.top, bounds.right, bounds.bottom);

    {
        MSG msg;
        BOOL res;
        while ((res = GetMessage(&msg, nullptr, 0, 0)) != -1)
        {
            if (msg.hwnd)
            {
                TranslateMessage(&msg);
                DispatchMessage(&msg);
                continue;
            }
            if (msg.message == WM_APP)
            {
                // auto f = (dispatch_fn_t *)(msg.lParam);
                // (*f)();
                // delete f;
            }
            else if (msg.message == WM_QUIT)
            {
                return 0;
            }
        }
    }

    return 0;
}