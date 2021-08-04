#ifndef WEBVIEW_EDGE
#error WEBVIEW_EDGE must be defined. This is a implementation file!
#endif

#define WEBVIEW_WINDOWS_CHROMIUM
// #define WEBVIEW_WINDOWS_EDGEHTML

//
// ====================================================================
//
// This implementation uses Win32 API to create a native window. It can
// use either EdgeHTML or Edge/Chromium backend as a browser engine.
//
// ====================================================================
//

#define WIN32_LEAN_AND_MEAN
#include <Shlwapi.h>
#include <codecvt>
#include <stdlib.h>
#include <windows.h>
#include <WinUser.h>

extern "C" WINUSERAPI BOOL WINAPI SetProcessDpiAwarenessContext(
    _In_ DPI_AWARENESS_CONTEXT value);

// #define DPI_AWARENESS_CONTEXT_UNAWARE ((DPI_AWARENESS_CONTEXT)-1)
// #define DPI_AWARENESS_CONTEXT_SYSTEM_AWARE ((DPI_AWARENESS_CONTEXT)-2)
// #define DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE ((DPI_AWARENESS_CONTEXT)-3)
// #define DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 ((DPI_AWARENESS_CONTEXT)-4)
// #define DPI_AWARENESS_CONTEXT_UNAWARE_GDISCALED ((DPI_AWARENESS_CONTEXT)-5)

// #pragma comment(lib, "user32.lib")
// #pragma comment(lib, "Shlwapi.lib")

using msg_cb_t = std::function<void(const std::string)>;

// Common interface for EdgeHTML and Edge/Chromium
class browser
{
public:
  virtual ~browser() = default;
  virtual bool embed(HWND, bool, msg_cb_t) = 0;
  virtual void navigate(const std::string url) = 0;
  virtual void eval(const std::string js) = 0;
  virtual void init(const std::string js) = 0;
  virtual void resize(HWND) = 0;
};

#ifdef WEBVIEW_WINDOWS_CHROMIUM
#include "webview-windows-chromium.h"
#endif
#ifdef WEBVIEW_WINDOWS_EDGEHTML
#include "webview-windows-edgehtml.h"
#endif

class browser_engine
{
public:
  static LRESULT wndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
  {
    auto w = (browser_engine *)GetWindowLongPtr(hwnd, GWLP_USERDATA);
    switch (msg)
    {
    case WM_SIZE:
      if (w->m_browser)
        w->m_browser->resize(hwnd);
      break;
    case WM_CLOSE:
      DestroyWindow(hwnd);
      break;
    case WM_DESTROY:
      w->terminate();
      break;
    case WM_PAINT:

      break;
    case WM_GETMINMAXINFO:
    {
      auto lpmmi = (LPMINMAXINFO)lp;
      if (w == nullptr)
      {
        return 0;
      }
      if (w->m_maxsz.x > 0 && w->m_maxsz.y > 0)
      {
        lpmmi->ptMaxSize = w->m_maxsz;
        lpmmi->ptMaxTrackSize = w->m_maxsz;
      }
      if (w->m_minsz.x > 0 && w->m_minsz.y > 0)
      {
        lpmmi->ptMinTrackSize = w->m_minsz;
      }
    }
    break;
    default:
      return DefWindowProc(hwnd, msg, wp, lp);
    }
    return 0;
  }

  browser_engine(bool debug, void *window)
  {

    if (window == nullptr)
    {
      HINSTANCE hInstance = GetModuleHandle(nullptr);
      HICON icon = (HICON)LoadImage(
          hInstance, IDI_APPLICATION, IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
          GetSystemMetrics(SM_CYSMICON), LR_DEFAULTCOLOR);

      WNDCLASSEX wc;
      ZeroMemory(&wc, sizeof(WNDCLASSEX));
      wc.cbSize = sizeof(WNDCLASSEX);
      wc.hInstance = hInstance;
      wc.lpszClassName = "webview";
      wc.hIcon = icon;
      wc.hIconSm = icon;
      wc.lpfnWndProc = wndProc;
      RegisterClassEx(&wc);
      m_window = CreateWindow("webview", "", WS_OVERLAPPEDWINDOW, CW_USEDEFAULT,
                              CW_USEDEFAULT, 640, 480, nullptr, nullptr,
                              GetModuleHandle(nullptr), nullptr);
      SetWindowLongPtr(m_window, GWLP_USERDATA, (LONG_PTR)this);
    }
    else
    {
      m_window = *(static_cast<HWND *>(window));
    }

    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE);
    ShowWindow(m_window, SW_SHOW);
    UpdateWindow(m_window);
    SetFocus(m_window);

    if (this->startBrowserEngine(debug))
    {
      this->m_browser->resize(m_window);
    }
  }

  bool
  startBrowserEngine(bool debug)
  {
    auto cb =
        std::bind(&browser_engine::on_message, this, std::placeholders::_1);
#ifdef WEBVIEW_WINDOWS_CHROMIUM
    this->m_browser = std::make_unique<edge_chromium>();
    if (this->m_browser->embed(m_window, debug, cb))
      return true;
#endif
#ifdef WEBVIEW_WINDOWS_EDGEHTML
    this->m_browser = std::make_unique<edge_html>();
    if (this->m_browser->embed(m_window, debug, cb))
      return true;
#endif
    this->m_browser.reset();
    return false;
  }

  void run()
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
        auto f = (dispatch_fn_t *)(msg.lParam);
        (*f)();
        delete f;
      }
      else if (msg.message == WM_QUIT)
      {
        return;
      }
    }
  }
  void *window() { return (void *)m_window; }
  void terminate() { PostQuitMessage(0); }
  void dispatch(dispatch_fn_t f)
  {
    PostThreadMessage(m_main_thread, WM_APP, 0, (LPARAM) new dispatch_fn_t(f));
  }

  void set_title(const std::string title)
  {
    SetWindowText(m_window, title.c_str());
  }

  void set_size(int width, int height, int hints)
  {
    auto style = GetWindowLong(m_window, GWL_STYLE);
    if (hints == WEBVIEW_HINT_FIXED)
    {
      style &= ~(WS_THICKFRAME | WS_MAXIMIZEBOX);
    }
    else
    {
      style |= (WS_THICKFRAME | WS_MAXIMIZEBOX);
    }
    SetWindowLong(m_window, GWL_STYLE, style);

    if (hints == WEBVIEW_HINT_MAX)
    {
      m_maxsz.x = width;
      m_maxsz.y = height;
    }
    else if (hints == WEBVIEW_HINT_MIN)
    {
      m_minsz.x = width;
      m_minsz.y = height;
    }
    else
    {
      RECT r;
      r.left = r.top = 0;
      r.right = width;
      r.bottom = height;
      AdjustWindowRect(&r, WS_OVERLAPPEDWINDOW, 0);
      SetWindowPos(m_window, NULL, r.left, r.top, r.right - r.left,
                   r.bottom - r.top,
                   SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOMOVE | SWP_FRAMECHANGED);
      m_browser->resize(m_window);
    }
  }

  void navigate(const std::string url) { m_browser->navigate(url); }
  void eval(const std::string js) { m_browser->eval(js); }
  void init(const std::string js) { m_browser->init(js); }

public:
  virtual void on_message(const std::string msg) = 0;

  HWND m_window;
  POINT m_minsz = POINT{0, 0};
  POINT m_maxsz = POINT{0, 0};
  DWORD m_main_thread = GetCurrentThreadId();
  std::unique_ptr<browser> m_browser;
};
