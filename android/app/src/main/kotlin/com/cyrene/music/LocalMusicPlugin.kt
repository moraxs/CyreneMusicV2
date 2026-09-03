package com.cyrene.music

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import java.nio.charset.Charset
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/// Android 本地音乐原生插件。
///
/// 背景：`file_picker` 在 Android 上选完文件会把内容拷贝到 app 缓存目录
/// （`path` 指向缓存文件），而选文件夹（`getDirectoryPath`）的返回值按
/// DocumentsProvider 的 tree id 拼装成一条不一定真实存在的 `/storage/...` 路径，
/// 二者都拿不到可供 `dart:io` 稳定读写的真实文件。于是这里用原生 SAF
/// （Storage Access Framework）重新实现两条导入通道。
///
/// **不再复制文件**：直接持久化 SAF 的 `content://` URI 权限，把原始 URI
/// 返回给 Flutter 端。播放由 media_kit 内部的 `AndroidContentUriProvider`
/// 把 `content://` 转为 `fd://` 供 libmpv 读取；元数据由 [readUriBytes] 通过
/// ContentResolver 读出字节后交 Dart 端解析。这样避免了把整库音频复制进
/// 应用私有目录导致的双倍存储占用。
///
/// - `pickFiles`：ACTION_OPEN_DOCUMENT 多选音频（含同名 .lrc 内容一并读取）
/// - `pickFolder`：ACTION_OPEN_DOCUMENT_TREE 选目录，递归扫描音频
/// - `readUriBytes`：读取单个 `content://` URI 的全部字节（供 Dart 解析元数据）
class LocalMusicPlugin : FlutterPlugin, ActivityAware, MethodCallHandler,
    ActivityResultListener {

    companion object {
        private const val TAG = "LocalMusicPlugin"
        private const val CHANNEL_NAME = "com.cyrene.music/local_music"

        private const val REQUEST_PICK_FILES = 2101
        private const val REQUEST_PICK_FOLDER = 2102

        private const val MAX_DIRECTORY_DEPTH = 20

        private val AUDIO_MIME_TYPES = arrayOf(
            "audio/mpeg",
            "audio/flac",
            "audio/wav",
            "audio/x-wav",
            "audio/mp4",
            "audio/x-m4a",
            "audio/aac",
            "audio/ogg",
            "audio/x-monkeys-audio",
            "audio/x-ape",
            "audio/ape",
            "audio/x-ms-wma",
            "application/octet-stream",
        )

        private val AUDIO_EXTENSIONS = setOf(
            "mp3", "flac", "wav", "m4a", "mp4", "aac", "ogg", "ape", "wma",
        )

        private const val LRC_EXTENSION = "lrc"
    }

    private var context: Context? = null
    private var activity: Activity? = null
    private var channel: MethodChannel? = null
    private var pendingResult: Result? = null

    private val ioExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler: Handler = Handler(Looper.getMainLooper())

    // -------------------------------------------------------------------------
    // FlutterPlugin / ActivityAware 生命周期
    // -------------------------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
        pendingResult?.error("detached", "Engine detached", null)
        pendingResult = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    // -------------------------------------------------------------------------
    // MethodChannel 入口
    // -------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "pickFiles" -> launchPickFiles(result)
            "pickFolder" -> launchPickFolder(result)
            "readUriBytes" -> {
                val uriStr = call.argument<String>("uri")
                if (uriStr.isNullOrEmpty()) {
                    result.error("invalid_argument", "uri is required", null)
                    return
                }
                ioExecutor.execute {
                    val bytes = readUriBytes(uriStr)
                    mainHandler.post {
                        if (bytes != null) {
                            result.success(bytes)
                        } else {
                            result.error("read_failed", "Unable to read $uriStr", null)
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun launchPickFiles(result: Result) {
        val ctx = activity ?: run {
            result.error("no_activity", "Local music picker requires a foreground activity", null)
            return
        }
        if (pendingResult != null) {
            result.error("already_active", "A local music picker is already active", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
            putExtra(Intent.EXTRA_MIME_TYPES, AUDIO_MIME_TYPES)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        try {
            ctx.startActivityForResult(intent, REQUEST_PICK_FILES)
        } catch (e: Exception) {
            pendingResult = null
            result.error("pick_failed", "Unable to open document picker", e.message)
        }
    }

    private fun launchPickFolder(result: Result) {
        val ctx = activity ?: run {
            result.error("no_activity", "Local music picker requires a foreground activity", null)
            return
        }
        if (pendingResult != null) {
            result.error("already_active", "A local music picker is already active", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        try {
            ctx.startActivityForResult(intent, REQUEST_PICK_FOLDER)
        } catch (e: Exception) {
            pendingResult = null
            result.error("pick_failed", "Unable to open directory picker", e.message)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK_FILES && requestCode != REQUEST_PICK_FOLDER) {
            return false
        }
        val result = pendingResult
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            result?.success(null)
            return true
        }

        // 文件/目录读取和复制为高耗时 I/O 操作，严禁在主线程执行；切换至子线程处理。
        ioExecutor.execute {
            try {
                val imported = if (requestCode == REQUEST_PICK_FILES) {
                    handlePickedFiles(data)
                } else {
                    handlePickedFolder(data)
                }
                val resultMap = imported.map { it.toMap() }
                mainHandler.post {
                    result?.success(resultMap)
                }
            } catch (e: Exception) {
                Log.e(TAG, "import failed", e)
                mainHandler.post {
                    result?.error("import_failed", e.message ?: "Import failed", null)
                }
            }
        }
        return true
    }

    // -------------------------------------------------------------------------
    // 选文件 / 选文件夹处理 (运行于 IO 线程)
    // -------------------------------------------------------------------------

    private fun handlePickedFiles(data: Intent): List<ImportedTrack> {
        val ctx = context ?: return emptyList()
        val uris = mutableListOf<Uri>()
        data.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
        }
        // 多选时结果走 clipData，单选时走 data.data；避免两者同时命中导致重复导入。
        if (uris.isEmpty()) {
            data.data?.let { uris.add(it) }
        }

        // 持久化每个所选 URI 的读权限，使应用重启后仍可访问（content:// URI
        // 的权限随 app 签名绑定，重装会失效，但重启不会）。
        for (uri in uris) {
            try {
                ctx.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            } catch (e: Exception) {
                Log.w(TAG, "takePersistableUriPermission failed for $uri", e)
            }
        }

        // 先收集同批选中的 .lrc，建立「文件名(不含扩展名) → 内容」映射，
        // 供音频文件导入时查找同名歌词。
        val lrcByBaseName = mutableMapOf<String, String>()
        val audioUris = mutableListOf<Uri>()
        for (uri in uris) {
            val name = queryDisplayName(ctx, uri) ?: continue
            val ext = name.substringAfterLast('.', "").lowercase(Locale.ROOT)
            if (ext == LRC_EXTENSION) {
                readLrcContent(ctx, uri)?.let { lrcByBaseName[name.substringBeforeLast('.')] = it }
            } else if (isSupportedAudio(ctx, uri)) {
                audioUris.add(uri)
            }
        }

        val tracks = mutableListOf<ImportedTrack>()
        for (uri in audioUris) {
            val name = queryDisplayName(ctx, uri) ?: continue
            val baseName = name.substringBeforeLast('.')
            tracks.add(
                ImportedTrack(
                    uri = uri.toString(),
                    displayName = name,
                    sidecarLrc = lrcByBaseName[baseName],
                )
            )
        }
        return tracks
    }

    private fun handlePickedFolder(data: Intent): List<ImportedTrack> {
        val ctx = context ?: return emptyList()
        val treeUri = data.data ?: return emptyList()
        try {
            ctx.contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (e: Exception) {
            Log.w(TAG, "takePersistableUriPermission failed", e)
        }
        val rootDocId = DocumentsContract.getTreeDocumentId(treeUri) ?: return emptyList()
        val tracks = mutableListOf<ImportedTrack>()
        val visited = mutableSetOf<String>()
        scanDirectory(ctx, treeUri, rootDocId, visited, 0, tracks)
        return tracks
    }

    /// 递归遍历所选目录树，找到音频文件后直接收集其 content:// URI（不复制）。
    ///
    /// [treeUri] 始终为根 Tree URI，[dirDocId] 为当前目录的 document ID。
    /// 必须使用 `buildChildDocumentsUriUsingTree(treeUri, dirDocId)`，避免将
    /// childUri 当成 treeUri 导致的死循环。子文档 URI 的访问依赖根 treeUri
    /// 的持久化权限，无需为每个子 URI 单独 takePersistableUriPermission。
    private fun scanDirectory(
        ctx: Context,
        treeUri: Uri,
        dirDocId: String,
        visitedDocIds: MutableSet<String>,
        depth: Int,
        out: MutableList<ImportedTrack>,
    ) {
        if (depth > MAX_DIRECTORY_DEPTH || !visitedDocIds.add(dirDocId)) {
            return
        }

        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, dirDocId)
        val cursor = try {
            ctx.contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                ),
                null, null, null,
            )
        } catch (e: Exception) {
            Log.w(TAG, "query children failed for $dirDocId", e)
            null
        } ?: return

        val lrcByBaseName = mutableMapOf<String, String>()
        val pendingAudio = mutableListOf<Pair<Uri, String>>()
        val subDirs = mutableListOf<String>()

        try {
            while (cursor.moveToNext()) {
                val childDocId = cursor.getString(0) ?: continue
                val displayName = cursor.getString(1)
                val mimeType = cursor.getString(2) ?: ""

                if (DocumentsContract.Document.MIME_TYPE_DIR == mimeType) {
                    subDirs.add(childDocId)
                } else if (displayName != null) {
                    val childUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, childDocId)
                    val ext = displayName.substringAfterLast('.', "").lowercase(Locale.ROOT)
                    when {
                        ext == LRC_EXTENSION -> {
                            readLrcContent(ctx, childUri)?.let {
                                lrcByBaseName[displayName.substringBeforeLast('.')] = it
                            }
                        }
                        isSupportedAudio(mimeType, displayName) -> {
                            pendingAudio.add(childUri to displayName)
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "iterating cursor failed", e)
        } finally {
            try {
                cursor.close()
            } catch (_: Exception) {}
        }

        for ((uri, name) in pendingAudio) {
            val baseName = name.substringBeforeLast('.')
            out.add(
                ImportedTrack(
                    uri = uri.toString(),
                    displayName = name,
                    sidecarLrc = lrcByBaseName[baseName],
                )
            )
        }

        for (subDirDocId in subDirs) {
            scanDirectory(ctx, treeUri, subDirDocId, visitedDocIds, depth + 1, out)
        }
    }

    private fun isSupportedAudio(ctx: Context, uri: Uri): Boolean {
        val name = queryDisplayName(ctx, uri) ?: ""
        val mime = ctx.contentResolver.getType(uri) ?: ""
        return isSupportedAudio(mime, name)
    }

    private fun isSupportedAudio(mimeType: String, displayName: String?): Boolean {
        val ext = displayName?.substringAfterLast('.', "")?.lowercase(Locale.ROOT)
        if (!ext.isNullOrEmpty()) {
            return AUDIO_EXTENSIONS.contains(ext)
        }
        return mimeType.startsWith("audio/")
    }

    // -------------------------------------------------------------------------
    // ContentResolver 读取（供 Dart 端解析元数据）
    // -------------------------------------------------------------------------

    /// 读取 `content://` URI 的全部字节。供 Dart 端 [AudioMetadataReader] 解析
    /// 元数据使用。失败返回 null。
    private fun readUriBytes(uriStr: String): ByteArray? {
        val ctx = context ?: return null
        return try {
            val uri = Uri.parse(uriStr)
            ctx.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (e: Exception) {
            Log.e(TAG, "readUriBytes failed: $uriStr", e)
            null
        }
    }

    private fun readLrcContent(ctx: Context, uri: Uri): String? {
        return try {
            ctx.contentResolver.openInputStream(uri)?.use { input ->
                val bytes = input.readBytes()
                // .lrc 常见 UTF-8 与 GBK；交给 Dart 端统一按字节解码（避免原生引入字符集库）
                String(bytes, Charsets.UTF_8).let { text ->
                    if (text.contains('\uFFFD')) {
                        String(bytes, Charset.forName("GBK"))
                    } else {
                        text
                    }
                }
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun queryDisplayName(ctx: Context, uri: Uri): String? {
        return try {
            ctx.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null, null, null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (e: Exception) {
            null
        }
    }
}

/// 单个成功导入的音轨，映射为 Dart 侧可读的 map。
///
/// [uri] 为 SAF 返回的 `content://` URI 字符串，作为曲目的主键与播放地址；
/// [sidecarLrc] 为同名 .lrc 的文本内容（已解码），无则 null。
data class ImportedTrack(
    val uri: String,
    val displayName: String,
    val sidecarLrc: String?,
) {
    fun toMap(): Map<String, Any?> {
        return hashMapOf<String, Any?>(
            "filePath" to uri,
            "displayName" to displayName,
            "sidecarLrc" to sidecarLrc,
        )
    }
}
