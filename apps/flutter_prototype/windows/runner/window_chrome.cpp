#include "win32_window.h"
#include <dwmapi.h>
#include <windowsx.h>
#include <algorithm>

namespace {
int Px(HWND w, int v) { return MulDiv(v, static_cast<int>(GetDpiForWindow(w)), 96); }
int Edge(HWND w) {
  const auto dpi = GetDpiForWindow(w);
  return GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) + GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
}
bool Button(int hit) { return hit == HTMINBUTTON || hit == HTMAXBUTTON || hit == HTCLOSE; }
COLORREF Dim(COLORREF c, double alpha) {
  return RGB(static_cast<int>(GetRValue(c) * (1 - alpha)),
             static_cast<int>(GetGValue(c) * (1 - alpha)),
             static_cast<int>(GetBValue(c) * (1 - alpha)));
}
}

void Win32Window::SetChrome(bool dark, const std::wstring& title) {
  chrome_dark_ = dark;
  SetWindowTextW(window_handle_, title.c_str());
  BOOL value = dark;
  DwmSetWindowAttribute(window_handle_, 20, &value, sizeof(value));
  PaintChrome();
}
void Win32Window::SetModalOpacity(double opacity) {
  modal_opacity_ = std::clamp(opacity, 0.0, 1.0);
  hover_hit_ = pressed_hit_ = 0;
  PaintChrome();
}
RECT Win32Window::CaptionRect(int hit) {
  RECT r{}; GetWindowRect(window_handle_, &r);
  const int edge = Edge(window_handle_);
  const int width = Px(window_handle_, 46);
  const int index = hit == HTCLOSE ? 0 : hit == HTMAXBUTTON ? 1 : 2;
  const int right = r.right-r.left-edge-index*width;
  return RECT{right-width, edge, right, edge+Px(window_handle_, 36)};
}
int Win32Window::ChromeHit(POINT screen) {
  RECT r{}; GetWindowRect(window_handle_, &r);
  POINT pt{screen.x-r.left, screen.y-r.top};
  const int edge = Edge(window_handle_);
  const int width = r.right-r.left, height = r.bottom-r.top;
  if (!IsZoomed(window_handle_)) {
    const bool left = pt.x < edge, right = pt.x >= width-edge;
    const bool top = pt.y < edge, bottom = pt.y >= height-edge;
    if (top) return left ? HTTOPLEFT : right ? HTTOPRIGHT : HTTOP;
    if (bottom) return left ? HTBOTTOMLEFT : right ? HTBOTTOMRIGHT : HTBOTTOM;
    if (left) return HTLEFT;
    if (right) return HTRIGHT;
  }
  if (pt.y < edge+Px(window_handle_, 36)) {
    if (modal_opacity_ > 0) return HTBORDER;
    for (int hit : {HTCLOSE, HTMAXBUTTON, HTMINBUTTON}) {
      RECT button = CaptionRect(hit);
      if (PtInRect(&button, pt)) return hit;
    }
    return HTCAPTION;
  }
  return HTCLIENT;
}
void Win32Window::PaintChrome(bool title_only) {
  if (!window_handle_ || IsIconic(window_handle_)) return;
  HDC target = GetWindowDC(window_handle_);
  if (!target) return;
  RECT frame{}; GetWindowRect(window_handle_, &frame);
  OffsetRect(&frame, -frame.left, -frame.top);
  RECT client{}; GetClientRect(window_handle_, &client);
  POINT origin{0,0}; ClientToScreen(window_handle_, &origin);
  RECT screen{}; GetWindowRect(window_handle_, &screen);
  OffsetRect(&client, origin.x-screen.left, origin.y-screen.top);
  // Never paint Flutter content. Hover changes are confined to the title strip.
  ExcludeClipRect(target, client.left, client.top, client.right, client.bottom);
  if (title_only) IntersectClipRect(target, 0, 0, frame.right, client.top);
  const int height = title_only ? client.top : frame.bottom;
  HDC dc = CreateCompatibleDC(target);
  HBITMAP bitmap = CreateCompatibleBitmap(target, frame.right, height);
  if (!dc || !bitmap) {
    if (dc) DeleteDC(dc);
    if (bitmap) DeleteObject(bitmap);
    ReleaseDC(window_handle_, target);
    return;
  }
  auto old_bitmap = SelectObject(dc, bitmap);
  COLORREF bg = Dim(chrome_dark_ ? RGB(26,26,26) : RGB(242,245,249), modal_opacity_);
  HBRUSH brush = CreateSolidBrush(bg); FillRect(dc, &frame, brush); DeleteObject(brush);
  SetBkMode(dc, TRANSPARENT);
  const COLORREF foreground = Dim(chrome_dark_ ? RGB(220,220,220) : RGB(60,60,60), modal_opacity_);
  SetTextColor(dc, foreground);
  HFONT font = CreateFontW(-Px(window_handle_,12), 0, 0, 0, FW_MEDIUM, FALSE, FALSE, FALSE,
                           DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                           CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
  auto old_font = SelectObject(dc, font);
  wchar_t title[512]{}; GetWindowTextW(window_handle_, title, 512);
  RECT text{Px(window_handle_,150), Edge(window_handle_), frame.right-Px(window_handle_,150), client.top};
  DrawTextW(dc, title, -1, &text, DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_END_ELLIPSIS|DT_NOPREFIX);
  SelectObject(dc, old_font); DeleteObject(font);
  for (int hit : {HTMINBUTTON, HTMAXBUTTON, HTCLOSE}) {
    RECT button = CaptionRect(hit);
    COLORREF color = foreground;
    if (hover_hit_ == hit && modal_opacity_ == 0) {
      const bool pressed = pressed_hit_ == hit;
      COLORREF highlight = hit == HTCLOSE ? (pressed ? RGB(180,20,30) : RGB(220,35,45))
          : chrome_dark_ ? (pressed ? RGB(75,75,75) : RGB(55,55,55))
                         : (pressed ? RGB(205,210,218) : RGB(225,230,237));
      HBRUSH fill = CreateSolidBrush(highlight); FillRect(dc, &button, fill); DeleteObject(fill);
      if (hit == HTCLOSE) color = RGB(255,255,255);
    }
    HPEN pen = CreatePen(PS_SOLID, std::max(1,Px(window_handle_,1)), color);
    auto old_pen = SelectObject(dc, pen);
    auto old_brush = SelectObject(dc, GetStockObject(NULL_BRUSH));
    const int x=(button.left+button.right)/2, y=(button.top+button.bottom)/2;
    const int d=Px(window_handle_,5);
    if (hit == HTMINBUTTON) { MoveToEx(dc,x-d,y,nullptr); LineTo(dc,x+d,y); }
    else if (hit == HTCLOSE) {
      MoveToEx(dc,x-d,y-d,nullptr); LineTo(dc,x+d,y+d);
      MoveToEx(dc,x+d,y-d,nullptr); LineTo(dc,x-d,y+d);
    } else if (IsZoomed(window_handle_)) {
      Rectangle(dc,x-d+Px(window_handle_,2),y-d,x+d+Px(window_handle_,2),y+d);
      HBRUSH fill=CreateSolidBrush(bg); RECT front{x-d,y-d+Px(window_handle_,2),x+d,y+d+Px(window_handle_,2)};
      FillRect(dc,&front,fill); DeleteObject(fill); Rectangle(dc,front.left,front.top,front.right,front.bottom);
    } else Rectangle(dc,x-d,y-d,x+d,y+d);
    SelectObject(dc,old_brush); SelectObject(dc,old_pen); DeleteObject(pen);
  }
  // Present background, text and glyphs together instead of exposing erase steps.
  BitBlt(target, 0, 0, frame.right, height, dc, 0, 0, SRCCOPY);
  SelectObject(dc, old_bitmap); DeleteObject(bitmap); DeleteDC(dc);
  ReleaseDC(window_handle_,target);
}
std::optional<LRESULT> Win32Window::ChromeMessage(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) {
  switch (message) {
    case WM_NCCALCSIZE: {
      RECT* rect = wp ? &reinterpret_cast<NCCALCSIZE_PARAMS*>(lp)->rgrc[0] : reinterpret_cast<RECT*>(lp);
      const LONG top = rect->top;
      // Keep the system resize frame and maximized work-area handling.
      DefWindowProc(hwnd,message,wp,lp);
      rect->top = top + Edge(hwnd) + Px(hwnd,36);
      return 0;
    }
    case WM_SETCURSOR:
      if (modal_opacity_ == 0 && Button(LOWORD(lp))) {
        SetCursor(LoadCursor(nullptr, IDC_ARROW));
        return TRUE;
      }
      break;
    case WM_NCHITTEST:
      return ChromeHit(POINT{GET_X_LPARAM(lp),GET_Y_LPARAM(lp)});
    case WM_NCPAINT: PaintChrome(); return 0;
    case WM_NCACTIVATE:
      DefWindowProc(hwnd,message,wp,-1); PaintChrome(); return TRUE;
    case WM_NCMOUSEMOVE: {
      const int next = modal_opacity_ == 0 && Button(static_cast<int>(wp)) ? static_cast<int>(wp) : 0;
      TRACKMOUSEEVENT track{sizeof(TRACKMOUSEEVENT),TME_LEAVE|TME_NONCLIENT,hwnd,0};
      TrackMouseEvent(&track);
      // Notify DWM of maximize hover for Snap Layouts, without asking
      // DefWindowProc to draw the stock caption over our custom frame.
      LRESULT ignored = 0;
      DwmDefWindowProc(hwnd,message,wp,lp,&ignored);
      if (hover_hit_ != next) { hover_hit_ = next; PaintChrome(true); }
      return 0;
    }
    case WM_NCMOUSELEAVE: {
      LRESULT ignored = 0;
      DwmDefWindowProc(hwnd,message,wp,lp,&ignored);
      if (hover_hit_ != 0) { hover_hit_=0; PaintChrome(true); }
      return 0;
    }
    case WM_NCLBUTTONDOWN:
      if (Button(static_cast<int>(wp)) && modal_opacity_ == 0) {
        pressed_hit_=static_cast<int>(wp); SetCapture(hwnd); PaintChrome(true); return 0;
      }
      break;
    case WM_MOUSEMOVE:
      if (pressed_hit_) {
        POINT pt{GET_X_LPARAM(lp),GET_Y_LPARAM(lp)}; ClientToScreen(hwnd,&pt);
        const int hit=ChromeHit(pt);
        const int next=Button(hit) ? hit : 0;
        if (hover_hit_ != next) { hover_hit_=next; PaintChrome(true); }
        return 0;
      }
      break;
    case WM_LBUTTONUP:
      if (pressed_hit_) {
        POINT pt{GET_X_LPARAM(lp),GET_Y_LPARAM(lp)}; ClientToScreen(hwnd,&pt);
        const int pressed=pressed_hit_; pressed_hit_=0; ReleaseCapture();
        if (ChromeHit(pt)==pressed && modal_opacity_==0) {
          const WPARAM command=pressed==HTCLOSE ? SC_CLOSE : pressed==HTMINBUTTON ? SC_MINIMIZE
              : IsZoomed(hwnd) ? SC_RESTORE : SC_MAXIMIZE;
          PostMessage(hwnd,WM_SYSCOMMAND,command,0);
        }
        PaintChrome(); return 0;
      }
      break;
    case WM_CAPTURECHANGED: pressed_hit_=0; PaintChrome(true); break;
    case WM_SIZE: PaintChrome(); break;
    case WM_DPICHANGED: hover_hit_=0; break;
    case WM_SETTEXT: {
      LRESULT result=DefWindowProc(hwnd,message,wp,lp); PaintChrome(); return result;
    }
  }
  return std::nullopt;
}
