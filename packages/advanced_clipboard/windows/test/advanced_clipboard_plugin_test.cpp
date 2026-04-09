#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <memory>
#include <string>
#include <variant>

#include "advanced_clipboard_plugin.h"

namespace advanced_clipboard {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

}  // namespace

TEST(AdvancedClipboardPlugin, GetPlatformVersion) {
  AdvancedClipboardPlugin plugin;
  // Save the reply value from the success callback.
  std::string result_string;
  plugin.HandleMethodCall(
      MethodCall("getPlatformVersion", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          [&result_string](const EncodableValue* result) {
            result_string = std::get<std::string>(*result);
          },
          nullptr, nullptr));

  // Since the exact string varies by host, just ensure that it's a string
  // with the expected format.
  EXPECT_TRUE(result_string.rfind("Windows ", 0) == 0);
}

TEST(AdvancedClipboardPlugin, StartStopListening) {
  AdvancedClipboardPlugin plugin;

  // Test startListening
  bool start_result = false;
  plugin.HandleMethodCall(
      MethodCall("startListening", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          [&start_result](const EncodableValue* result) {
            start_result = true;  // Success callback means it worked
          },
          nullptr, nullptr));

  // Test stopListening
  bool stop_result = false;
  plugin.HandleMethodCall(
      MethodCall("stopListening", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          [&stop_result](const EncodableValue* result) {
            stop_result = true;  // Success callback means it worked
          },
          nullptr, nullptr));

  // The methods should complete without throwing
  EXPECT_TRUE(start_result);
  EXPECT_TRUE(stop_result);
}

}  // namespace test
}  // namespace advanced_clipboard
