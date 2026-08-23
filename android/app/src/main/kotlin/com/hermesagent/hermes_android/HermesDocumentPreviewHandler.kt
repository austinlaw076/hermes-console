package com.hermesagent.hermes_android

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import kotlin.math.roundToInt

/**
 * Rasteriza páginas PDF desde el almacén privado de adjuntos enviados.
 *
 * El canal solo acepta una clave SHA-256, nunca una ruta. Antes de abrir el
 * descriptor revalida raíz canónica, tamaño y digest; un symlink, traversal o
 * marcador manipulado falla cerrado. No lanza intents ni exporta los bytes.
 */
class HermesDocumentPreviewHandler(
    context: Context,
) : MethodChannel.MethodCallHandler, AutoCloseable {
    private val filesRoot = context.filesDir.canonicalFile
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "renderPdfPage") {
            result.notImplemented()
            return
        }
        val storageKey = call.argument<String>("storageKey").orEmpty()
        val pageIndex = (call.argument<Number>("page"))?.toInt() ?: -1
        val expectedSize = (call.argument<Number>("expectedSize"))?.toLong() ?: -1L
        val expectedSha256 = call.argument<String>("expectedSha256").orEmpty()
        try {
            executor.execute {
                val response = runCatching {
                    renderPdfPage(
                        storageKey = storageKey,
                        pageIndex = pageIndex,
                        expectedSize = expectedSize,
                        expectedSha256 = expectedSha256,
                    )
                }
                mainHandler.post {
                    response.fold(
                        onSuccess = result::success,
                        onFailure = {
                            result.error(
                                "preview_unavailable",
                                "The private PDF preview is unavailable",
                                null,
                            )
                        },
                    )
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error(
                "preview_unavailable",
                "The private PDF preview is unavailable",
                null,
            )
        }
    }

    private fun renderPdfPage(
        storageKey: String,
        pageIndex: Int,
        expectedSize: Long,
        expectedSha256: String,
    ): Map<String, Any> {
        require(storageKey.matches(SHA256_PATTERN))
        require(expectedSha256 == storageKey)
        require(expectedSize in 1..MAX_ATTACHMENT_BYTES)
        val unresolvedDirectory = File(filesRoot, SENT_ATTACHMENTS_DIRECTORY).absoluteFile
        val directory = unresolvedDirectory.canonicalFile
        require(directory == unresolvedDirectory)
        require(directory.parentFile == filesRoot)
        require(directory.isDirectory)
        val unresolved = File(directory, storageKey).absoluteFile
        val file = unresolved.canonicalFile
        require(file == unresolved)
        require(file.parentFile == directory)
        require(file.isFile)
        require(file.length() == expectedSize)
        require(file.sha256() == expectedSha256)

        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
            PdfRenderer(descriptor).use { renderer ->
                require(pageIndex in 0 until renderer.pageCount)
                renderer.openPage(pageIndex).use { page ->
                    var width = minOf(MAX_RENDER_WIDTH, (page.width * 2).coerceAtLeast(1))
                    var height = (page.height * (width.toDouble() / page.width)).roundToInt()
                        .coerceAtLeast(1)
                    if (height > MAX_RENDER_HEIGHT) {
                        height = MAX_RENDER_HEIGHT
                        width = (page.width * (height.toDouble() / page.height)).roundToInt()
                            .coerceAtLeast(1)
                    }
                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    try {
                        bitmap.eraseColor(Color.WHITE)
                        page.render(
                            bitmap,
                            null,
                            null,
                            PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY,
                        )
                        val output = ByteArrayOutputStream()
                        require(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output))
                        return mapOf(
                            "pngBytes" to output.toByteArray(),
                            "pageCount" to renderer.pageCount,
                            "pageIndex" to pageIndex,
                        )
                    } finally {
                        bitmap.recycle()
                    }
                }
            }
        }
    }

    private fun File.sha256(): String {
        val digest = MessageDigest.getInstance("SHA-256")
        inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    }

    override fun close() {
        executor.shutdownNow()
    }

    private companion object {
        const val SENT_ATTACHMENTS_DIRECTORY = "sent_attachments"
        const val MAX_ATTACHMENT_BYTES = 8L * 1024L * 1024L
        const val MAX_RENDER_WIDTH = 1440
        const val MAX_RENDER_HEIGHT = 4096
        val SHA256_PATTERN = Regex("^[a-f0-9]{64}$")
    }
}
