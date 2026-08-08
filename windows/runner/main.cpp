#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cwchar>
#include <string>

#include <propkey.h>       // PKEY_AppUserModel_ID
#include <propsys.h>       // IPropertyStore
#include <shlguid.h>       // CLSID_ShellLink / IID_IShellLinkW
#include <shlobj.h>        // SHChangeNotify / SHCNE_* / SHCNF_*
#include <shobjidl.h>      // IShellLinkW / IPersistFile
#include <winrt/base.h>    // winrt::com_ptr

#include "flutter_window.h"
#include "utils.h"

namespace {

// ==================== 应用标识（SMTC 显示名） ====================
//
// 未打包 Win32 应用在系统媒体浮层（SMTC）/音量混音器中的名字由“应用条目”
// 决定：壳层先按进程的 AppUserModelID 找开始菜单里带相同 System.AppUserModel.ID
// 属性的快捷方式，再取其显示名。没有该条目时一律显示“未知应用”。
//
// 这解释了为何此前只设 AUMID + 写注册表仍显示“未知应用”——注册表 DisplayName
// 只是名字来源之一，壳层解析名字的前提是存在一个 App 条目。安装器（如 Folia
// 用的 NSIS）安装时创建快捷方式隐含完成了这步；`flutter run`/直接跑 exe 则没有。
// 这里在启动时幂等地补上。

// 固定的 AUMID，与 setAppUserModelId 一致，保证同一身份。
const wchar_t* kAppUserModelId = L"CyreneMusicReborn";
const wchar_t* kAppDisplayName = L"Cyrene Music";

// 进程绑定 AUMID + HKCU 注册 DisplayName（托盘/编辑解析的兜底）。
void RegisterAppDisplayIdentity() {
  HKEY hkey = nullptr;
  const std::wstring key =
      std::wstring(L"Software\\Classes\\AppUserModelId\\") + kAppUserModelId;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, key.c_str(), 0, nullptr, 0,
                        KEY_SET_VALUE, nullptr, &hkey,
                        nullptr) == ERROR_SUCCESS) {
    ::RegSetValueExW(
        hkey, L"DisplayName", 0, REG_SZ,
        reinterpret_cast<const BYTE*>(kAppDisplayName),
        static_cast<DWORD>((wcslen(kAppDisplayName) + 1) * sizeof(wchar_t)));
    ::RegCloseKey(hkey);
  }
  // 让进程携带该 AUMID；失败可忽略（仅影响显示名解析）。
  ::SetCurrentProcessExplicitAppUserModelID(kAppUserModelId);
}

// 在开始菜单创建带 System.AppUserModel.ID 属性的快捷方式，使壳层能把这
// 个 AUMID 解析成“Cyrene Music”。已存在则跳过（保持幂等）。
void RegisterStartMenuAppEntry() {
  wchar_t appdata[MAX_PATH] = L"";
  if (::GetEnvironmentVariableW(L"APPDATA", appdata, MAX_PATH) == 0) {
    return;
  }
  const std::wstring link_path =
      std::wstring(appdata) +
      L"\\Microsoft\\Windows\\Start Menu\\Programs\\Cyrene Music.lnk";
  if (::GetFileAttributesW(link_path.c_str()) != INVALID_FILE_ATTRIBUTES) {
    return;  // 已登记过。
  }

  wchar_t exe_path[MAX_PATH] = L"";
  if (::GetModuleFileNameW(nullptr, exe_path, MAX_PATH) == 0) {
    return;
  }
  std::wstring exe_dir(exe_path);
  const size_t slash = exe_dir.find_last_of(L'\\');
  exe_dir = (slash == std::wstring::npos) ? L"" : exe_dir.substr(0, slash);

  winrt::com_ptr<IShellLinkW> shell_link;
  if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                IID_IShellLinkW, shell_link.put_void()))) {
    return;
  }
  if (FAILED(shell_link->SetPath(exe_path))) {
    return;
  }
  shell_link->SetWorkingDirectory(exe_dir.c_str());
  shell_link->SetDescription(kAppDisplayName);
  shell_link->SetIconLocation(exe_path, 0);

  // 写入 AUMID 属性：壳层据此把快捷方式归到应用的 App 条目。显示名由
  // .lnk 文件名提供（“Cyrene Music.lnk”），无需额外的 DisplayName 属性
  // （本 SDK 亦无 PKEY_AppUserModel_DisplayName）。
  winrt::com_ptr<IPropertyStore> store = shell_link.try_as<IPropertyStore>();
  if (store) {
    PROPVARIANT aumid_pv{};
    aumid_pv.vt = VT_LPWSTR;
    aumid_pv.pwszVal = const_cast<wchar_t*>(kAppUserModelId);
    store->SetValue(PKEY_AppUserModel_ID, aumid_pv);
    store->Commit();
  }

  winrt::com_ptr<IPersistFile> persist = shell_link.try_as<IPersistFile>();
  if (persist && SUCCEEDED(persist->Save(link_path.c_str(), TRUE))) {
    // 通知 Shell 重新枚举，避免 Explorer 缓存旧状态。
    ::SHChangeNotify(SHCNE_CREATE, SHCNF_PATH, link_path.c_str(), nullptr);
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // 在创建媒体会话前建立应用身份：AUMID + 开始菜单 App 条目，使 SMTC/音量
  // 混音器显示“Cyrene Music”而非“未知应用”。
  RegisterAppDisplayIdentity();
  RegisterStartMenuAppEntry();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"cyrene_music_reborn", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
