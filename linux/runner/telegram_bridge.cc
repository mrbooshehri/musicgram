#include "telegram_bridge.h"

#include <dlfcn.h>
#include <cstring>

namespace {
using Create = int (*)();
using Send = void (*)(int, const char*);
using Receive = const char* (*)(double);
using Execute = const char* (*)(const char*);
void* library = nullptr;
Create create_client = nullptr;
Send send_request = nullptr;
Receive receive_update = nullptr;

bool load_library() {
  if (library != nullptr) return true;
  void* handle = dlopen("libtdjson.so", RTLD_NOW | RTLD_LOCAL);
  if (handle == nullptr) return false;
  auto create = reinterpret_cast<Create>(dlsym(handle, "td_create_client_id"));
  auto send = reinterpret_cast<Send>(dlsym(handle, "td_send"));
  auto receive = reinterpret_cast<Receive>(dlsym(handle, "td_receive"));
  auto execute = reinterpret_cast<Execute>(dlsym(handle, "td_execute"));
  if (create == nullptr || send == nullptr || receive == nullptr) {
    dlclose(handle);
    return false;
  }
  library = handle;
  create_client = create;
  send_request = send;
  receive_update = receive;
  if (execute != nullptr) {
    execute("{\"@type\":\"setLogVerbosityLevel\",\"new_verbosity_level\":0}");
  }
  return true;
}

void receive_worker(GTask* task, gpointer, gpointer, GCancellable*) {
  const char* update = receive_update(1.0);
  g_task_return_pointer(task, update == nullptr ? nullptr : g_strdup(update), g_free);
}

void receive_complete(GObject*, GAsyncResult* result, gpointer user_data) {
  auto* call = FL_METHOD_CALL(user_data);
  g_autofree gchar* update = static_cast<gchar*>(
      g_task_propagate_pointer(G_TASK(result), nullptr));
  g_autoptr(FlValue) value = update == nullptr ? fl_value_new_null()
                                              : fl_value_new_string(update);
  fl_method_call_respond_success(call, value, nullptr);
  g_object_unref(call);
}

void handle_call(FlMethodChannel*, FlMethodCall* call, gpointer) {
  if (!load_library()) {
    fl_method_call_respond_error(call, "tdlib_unavailable",
                                 "TDLib is not installed in the Linux bundle.",
                                 nullptr, nullptr);
    return;
  }
  const char* method = fl_method_call_get_name(call);
  if (std::strcmp(method, "create") == 0) {
    g_autoptr(FlValue) value = fl_value_new_int(create_client());
    fl_method_call_respond_success(call, value, nullptr);
  } else if (std::strcmp(method, "send") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    FlValue* id = args == nullptr ? nullptr : fl_value_lookup_string(args, "clientId");
    FlValue* request = args == nullptr ? nullptr : fl_value_lookup_string(args, "request");
    if (id == nullptr || request == nullptr ||
        fl_value_get_type(id) != FL_VALUE_TYPE_INT ||
        fl_value_get_type(request) != FL_VALUE_TYPE_STRING) {
      fl_method_call_respond_error(call, "invalid_argument", "Missing client ID or request", nullptr, nullptr);
      return;
    }
    send_request(static_cast<int>(fl_value_get_int(id)), fl_value_get_string(request));
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (std::strcmp(method, "receive") == 0) {
    g_autoptr(GTask) task = g_task_new(nullptr, nullptr, receive_complete, g_object_ref(call));
    g_task_run_in_thread(task, receive_worker);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}
}  // namespace

void telegram_bridge_register(FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      messenger, "musicgram/tdlib", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, handle_call, nullptr, nullptr);
}
