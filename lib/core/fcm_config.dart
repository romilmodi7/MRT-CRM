/// Phone notifications (Firebase). Fill these 4 values from the file google-services.json
/// (Firebase console > Project settings > General > Your apps > Android app "com.mindrippletech.employee_chat" > download google-services.json):
///
///   kFcmApiKey    -> "current_key"            (client > api_key > current_key)
///   kFcmAppId     -> "mobilesdk_app_id"       (client > client_info > mobilesdk_app_id, looks like 1:123456789:android:abc123)
///   kFcmSenderId  -> "project_number"         (project_info > project_number, digits only)
///   kFcmProjectId -> "project_id"             (project_info > project_id)
///
/// Left empty = the app works as before, just without phone notifications.
const String kFcmApiKey = 'AIzaSyDoQTe1gyCjm6en7LK3bCppLKhiab84cfY';
const String kFcmAppId = '1:765764116723:android:e738e239607b2d5d1c5786';
const String kFcmSenderId = '765764116723';
const String kFcmProjectId = 'mrt-crm-8d7a3';
