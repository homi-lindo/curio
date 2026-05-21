#include "secure_secrets.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <wincrypt.h>

#include <cctype>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace {

constexpr char kChannelName[] = "app.lume.personal/secure_secrets";
constexpr wchar_t kSecretDescription[] = L"Curi\u00F3 secure secret";

using GetCurrentPackageFamilyNameFn = LONG(WINAPI*)(UINT32*, PWSTR);

bool IsValidSecretKey(const std::string& key) {
  if (key.empty() || key.size() > 64) {
    return false;
  }

  for (const char unit : key) {
    const unsigned char value = static_cast<unsigned char>(unit);
    if (!std::isalnum(value) && unit != '.' && unit != '_' && unit != '-') {
      return false;
    }
  }
  return true;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }

  const int size = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }

  std::wstring output(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), output.data(), size);
  return output;
}

bool EnsureDirectory(const std::wstring& path) {
  if (::CreateDirectoryW(path.c_str(), nullptr) != 0) {
    return true;
  }

  return ::GetLastError() == ERROR_ALREADY_EXISTS;
}

std::wstring LocalAppDataDirectory() {
  const DWORD required = ::GetEnvironmentVariableW(L"LOCALAPPDATA", nullptr, 0);
  if (required == 0) {
    return std::wstring();
  }

  std::wstring local_app_data(static_cast<size_t>(required), L'\0');
  const DWORD written = ::GetEnvironmentVariableW(
      L"LOCALAPPDATA", local_app_data.data(), required);
  if (written == 0 || written >= required) {
    return std::wstring();
  }

  local_app_data.resize(written);
  return local_app_data;
}

GetCurrentPackageFamilyNameFn CurrentPackageFamilyNameReader() {
  HMODULE kernel32 = ::GetModuleHandleW(L"kernel32.dll");
  if (kernel32 == nullptr) {
    return nullptr;
  }

#pragma warning(push)
#pragma warning(disable : 4191)
  auto reader = reinterpret_cast<GetCurrentPackageFamilyNameFn>(
      ::GetProcAddress(kernel32, "GetCurrentPackageFamilyName"));
#pragma warning(pop)
  return reader;
}

std::wstring PackageLocalStateDirectory(const std::wstring& local_app_data) {
  const auto read_package_family_name = CurrentPackageFamilyNameReader();
  if (read_package_family_name == nullptr) {
    return std::wstring();
  }

  UINT32 package_family_length = 0;
  LONG result =
      read_package_family_name(&package_family_length, nullptr);
  if (result != ERROR_INSUFFICIENT_BUFFER || package_family_length == 0) {
    return std::wstring();
  }

  std::wstring package_family(package_family_length, L'\0');
  result =
      read_package_family_name(&package_family_length, package_family.data());
  if (result != ERROR_SUCCESS || package_family_length == 0) {
    return std::wstring();
  }

  if (!package_family.empty() && package_family.back() == L'\0') {
    package_family.pop_back();
  }
  return local_app_data + L"\\Packages\\" + package_family + L"\\LocalState";
}

std::wstring SecretDirectory() {
  const std::wstring local_app_data = LocalAppDataDirectory();
  if (local_app_data.empty()) {
    return std::wstring();
  }

  const std::wstring package_local_state =
      PackageLocalStateDirectory(local_app_data);
  const std::wstring app_dir =
      package_local_state.empty() ? local_app_data + L"\\Curio"
                                  : package_local_state;
  const std::wstring secrets_dir = app_dir + L"\\SecureSecrets";
  if (!EnsureDirectory(app_dir) || !EnsureDirectory(secrets_dir)) {
    return std::wstring();
  }
  return secrets_dir;
}

std::wstring SecretPath(const std::string& key) {
  const std::wstring directory = SecretDirectory();
  const std::wstring wide_key = Utf8ToWide(key);
  if (directory.empty() || wide_key.empty()) {
    return std::wstring();
  }
  return directory + L"\\" + wide_key + L".bin";
}

bool ReadFileBytes(const std::wstring& path, std::vector<uint8_t>* output) {
  HANDLE file = ::CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                              nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL,
                              nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return false;
  }

  LARGE_INTEGER size = {};
  if (::GetFileSizeEx(file, &size) == 0 || size.QuadPart < 0 ||
      size.QuadPart > 1024 * 1024) {
    ::CloseHandle(file);
    return false;
  }

  output->assign(static_cast<size_t>(size.QuadPart), 0);
  DWORD read = 0;
  const BOOL ok =
      output->empty() ||
      ::ReadFile(file, output->data(), static_cast<DWORD>(output->size()),
                 &read, nullptr);
  ::CloseHandle(file);
  return ok != 0 && static_cast<size_t>(read) == output->size();
}

bool WriteFileBytes(const std::wstring& path,
                    const std::vector<uint8_t>& bytes) {
  const std::wstring temp_path = path + L".tmp";
  HANDLE file =
      ::CreateFileW(temp_path.c_str(), GENERIC_WRITE, 0, nullptr,
                    CREATE_ALWAYS,
                    FILE_ATTRIBUTE_NORMAL | FILE_ATTRIBUTE_TEMPORARY, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return false;
  }

  DWORD written = 0;
  const BOOL ok =
      bytes.empty() ||
      ::WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()),
                  &written, nullptr);
  const BOOL flushed = ok != 0 && ::FlushFileBuffers(file) != 0;
  ::CloseHandle(file);
  if (flushed == 0 || static_cast<size_t>(written) != bytes.size()) {
    ::DeleteFileW(temp_path.c_str());
    return false;
  }

  if (::MoveFileExW(temp_path.c_str(), path.c_str(),
                    MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) == 0) {
    ::DeleteFileW(temp_path.c_str());
    return false;
  }

  return true;
}

bool ProtectSecret(const std::string& value, std::vector<uint8_t>* output) {
  DATA_BLOB input = {};
  input.pbData = reinterpret_cast<BYTE*>(
      const_cast<char*>(value.data()));
  input.cbData = static_cast<DWORD>(value.size());

  DATA_BLOB protected_blob = {};
  if (::CryptProtectData(&input, kSecretDescription, nullptr, nullptr, nullptr,
                         0, &protected_blob) == 0) {
    return false;
  }

  output->assign(protected_blob.pbData,
                 protected_blob.pbData + protected_blob.cbData);
  ::LocalFree(protected_blob.pbData);
  return true;
}

bool UnprotectSecret(const std::vector<uint8_t>& encrypted,
                     std::string* output) {
  DATA_BLOB input = {};
  input.pbData = const_cast<BYTE*>(encrypted.data());
  input.cbData = static_cast<DWORD>(encrypted.size());

  DATA_BLOB plain = {};
  if (::CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr, 0,
                           &plain) == 0) {
    return false;
  }

  output->assign(reinterpret_cast<char*>(plain.pbData), plain.cbData);
  ::LocalFree(plain.pbData);
  return true;
}

bool WriteSecret(const std::string& key, const std::string& value) {
  const std::wstring path = SecretPath(key);
  if (path.empty()) {
    return false;
  }

  std::vector<uint8_t> encrypted;
  if (!ProtectSecret(value, &encrypted)) {
    return false;
  }
  return WriteFileBytes(path, encrypted);
}

bool ReadSecret(const std::string& key, std::string* value) {
  const std::wstring path = SecretPath(key);
  if (path.empty()) {
    return false;
  }

  std::vector<uint8_t> encrypted;
  if (!ReadFileBytes(path, &encrypted)) {
    return false;
  }
  return UnprotectSecret(encrypted, value);
}

void DeleteSecret(const std::string& key) {
  const std::wstring path = SecretPath(key);
  if (!path.empty()) {
    ::DeleteFileW(path.c_str());
  }
}

const std::string* StringArgument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const char* name) {
  const auto* arguments =
      std::get_if<flutter::EncodableMap>(call.arguments());
  if (arguments == nullptr) {
    return nullptr;
  }

  const auto value = arguments->find(flutter::EncodableValue(name));
  if (value == arguments->end()) {
    return nullptr;
  }

  return std::get_if<std::string>(&value->second);
}

}  // namespace

void RegisterSecureSecretsChannel(flutter::BinaryMessenger* messenger) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        const std::string* key = StringArgument(call, "key");
        if (key == nullptr || !IsValidSecretKey(*key)) {
          result->Error("bad-arguments", "Invalid secret key.");
          return;
        }

        if (call.method_name() == "read") {
          std::string value;
          if (!ReadSecret(*key, &value)) {
            result->Success(flutter::EncodableValue());
            return;
          }
          result->Success(flutter::EncodableValue(value));
          return;
        }

        if (call.method_name() == "write") {
          const std::string* value = StringArgument(call, "value");
          if (value == nullptr) {
            result->Error("bad-arguments", "Missing secret value.");
            return;
          }
          if (value->empty()) {
            DeleteSecret(*key);
            result->Success();
            return;
          }
          if (!WriteSecret(*key, *value)) {
            result->Error("secure-secret-error",
                          "Secure storage unavailable.");
            return;
          }
          result->Success();
          return;
        }

        if (call.method_name() == "delete") {
          DeleteSecret(*key);
          result->Success();
          return;
        }

        result->NotImplemented();
      });

  channel.release();
}
