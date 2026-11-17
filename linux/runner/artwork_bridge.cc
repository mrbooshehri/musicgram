#include "artwork_bridge.h"

#include <gst/gst.h>
#include <gst/pbutils/pbutils.h>
#include <cstring>

namespace {
GBytes* image_from_tags(const GstTagList* tags) {
  if (tags == nullptr) return nullptr;
  GstSample* sample = nullptr;
  if (!gst_tag_list_get_sample(tags, GST_TAG_IMAGE, &sample) &&
      !gst_tag_list_get_sample(tags, GST_TAG_PREVIEW_IMAGE, &sample)) {
    return nullptr;
  }
  GstBuffer* buffer = gst_sample_get_buffer(sample);
  GstMapInfo mapped;
  GBytes* result = nullptr;
  if (buffer != nullptr && gst_buffer_map(buffer, &mapped, GST_MAP_READ)) {
    if (mapped.size > 0 && mapped.size <= 10 * 1024 * 1024) {
      result = g_bytes_new(mapped.data, mapped.size);
    }
    gst_buffer_unmap(buffer, &mapped);
  }
  gst_sample_unref(sample);
  return result;
}

void artwork_worker(GTask* task, gpointer, gpointer data, GCancellable*) {
  const char* path = static_cast<const char*>(data);
  g_autofree gchar* uri = g_filename_to_uri(path, nullptr, nullptr);
  if (uri == nullptr) {
    g_task_return_pointer(task, nullptr, nullptr);
    return;
  }
  g_autoptr(GError) error = nullptr;
  GstDiscoverer* discoverer = gst_discoverer_new(5 * GST_SECOND, &error);
  if (discoverer == nullptr) {
    g_task_return_pointer(task, nullptr, nullptr);
    return;
  }
  GstDiscovererInfo* info = gst_discoverer_discover_uri(discoverer, uri, &error);
  GBytes* image = info == nullptr ? nullptr : image_from_tags(gst_discoverer_info_get_tags(info));
  if (info != nullptr && image == nullptr) {
    GList* streams = gst_discoverer_info_get_stream_list(info);
    for (GList* item = streams; item != nullptr && image == nullptr; item = item->next) {
      auto* stream = GST_DISCOVERER_STREAM_INFO(item->data);
      image = image_from_tags(gst_discoverer_stream_info_get_tags(stream));
    }
    gst_discoverer_stream_info_list_free(streams);
  }
  if (info != nullptr) gst_discoverer_info_unref(info);
  g_object_unref(discoverer);
  g_task_return_pointer(task, image, image == nullptr ? nullptr : reinterpret_cast<GDestroyNotify>(g_bytes_unref));
}

void artwork_complete(GObject*, GAsyncResult* result, gpointer user_data) {
  auto* call = FL_METHOD_CALL(user_data);
  GBytes* image = static_cast<GBytes*>(g_task_propagate_pointer(G_TASK(result), nullptr));
  g_autoptr(FlValue) value = nullptr;
  if (image == nullptr) {
    value = fl_value_new_null();
  } else {
    gsize size = 0;
    const auto* bytes = static_cast<const uint8_t*>(g_bytes_get_data(image, &size));
    value = fl_value_new_uint8_list(bytes, size);
    g_bytes_unref(image);
  }
  fl_method_call_respond_success(call, value, nullptr);
  g_object_unref(call);
}

void handle_call(FlMethodChannel*, FlMethodCall* call, gpointer) {
  if (std::strcmp(fl_method_call_get_name(call), "artwork") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(call);
  FlValue* path = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                      ? fl_value_lookup_string(args, "path") : nullptr;
  if (path == nullptr || fl_value_get_type(path) != FL_VALUE_TYPE_STRING) {
    fl_method_call_respond_error(call, "invalid_argument", "Missing audio path", nullptr, nullptr);
    return;
  }
  g_autoptr(GTask) task = g_task_new(nullptr, nullptr, artwork_complete, g_object_ref(call));
  g_task_set_task_data(task, g_strdup(fl_value_get_string(path)), g_free);
  g_task_run_in_thread(task, artwork_worker);
}
}  // namespace

void artwork_bridge_register(FlBinaryMessenger* messenger) {
  gst_init(nullptr, nullptr);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      messenger, "musicgram/library", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, handle_call, nullptr, nullptr);
}
