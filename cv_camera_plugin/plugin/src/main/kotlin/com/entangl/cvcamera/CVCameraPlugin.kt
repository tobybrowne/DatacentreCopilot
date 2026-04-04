package com.entangl.cvcamera

import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.hardware.camera2.*
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.io.ByteArrayOutputStream

class CVCameraPlugin(godot: Godot) : GodotPlugin(godot) {

    override fun getPluginName() = "CVCamera"

    private val thread = HandlerThread("CVCameraThread").also { it.start() }
    private val handler = Handler(thread.looper)

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null

    // -1 = auto, otherwise manual values set via setExposure() / setNoiseReduction()
    private var exposureTimeNs: Long = -1L
    private var sensitivity: Int = -1
    private var noiseReductionOff: Boolean = false

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    // exposureMs: shutter time in milliseconds (e.g. 4.0 = 1/250s), -1 for auto
    // iso: sensor sensitivity (e.g. 800), -1 for auto
    @UsedByGodot
    fun setExposure(exposureMs: Double, iso: Int) {
        exposureTimeNs = if (exposureMs < 0) -1L else (exposureMs * 1_000_000.0).toLong()
        sensitivity = iso
    }

    @UsedByGodot
    fun setNoiseReduction(enabled: Boolean) {
        noiseReductionOff = !enabled
    }

    @UsedByGodot
    fun openCamera(width: Int, height: Int) {
        imageReader = ImageReader.newInstance(width, height, ImageFormat.YUV_420_888, 2)

        val manager = godot.getActivity()!!
            .getSystemService(android.content.Context.CAMERA_SERVICE) as CameraManager

        try {
            manager.openCamera("1", object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    createSession()
                }
                override fun onDisconnected(camera: CameraDevice) {
                    camera.close()
                    cameraDevice = null
                    emitSignal("camera_closed")
                }
                override fun onError(camera: CameraDevice, error: Int) {
                    camera.close()
                    cameraDevice = null
                    emitSignal("camera_error", error)
                }
            }, handler)
        } catch (e: SecurityException) {
            emitSignal("camera_error", -1)
        }
    }

    @UsedByGodot
    fun captureFrame() {
        val session = captureSession ?: run { emitSignal("camera_error", -2); return }
        val camera = cameraDevice ?: run { emitSignal("camera_error", -2); return }
        val reader = imageReader ?: return

        reader.setOnImageAvailableListener({ r ->
            r.setOnImageAvailableListener(null, null)
            val image = r.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                emitSignal("frame_available", imageToJpeg(image))
            } finally {
                image.close()
            }
        }, handler)

        val request = camera
            // TEMPLATE_PREVIEW gives a single raw frame with no multi-frame compositing.
            // TEMPLATE_STILL_CAPTURE on ML2 blends previous frames into the output,
            // producing a ghost overlay of wherever the headset was pointing before.
            .createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
            .apply {
                addTarget(reader.surface)
                if (noiseReductionOff) {
                    set(CaptureRequest.NOISE_REDUCTION_MODE, CaptureRequest.NOISE_REDUCTION_MODE_OFF)
                    set(CaptureRequest.EDGE_MODE, CaptureRequest.EDGE_MODE_OFF)
                }
                if (exposureTimeNs > 0 && sensitivity > 0) {
                    set(CaptureRequest.CONTROL_AE_MODE, CameraMetadata.CONTROL_AE_MODE_OFF)
                    set(CaptureRequest.SENSOR_EXPOSURE_TIME, exposureTimeNs)
                    set(CaptureRequest.SENSOR_SENSITIVITY, sensitivity)
                }
            }
            .build()

        session.capture(request, null, handler)
    }

    @UsedByGodot
    fun closeCamera() {
        captureSession?.close()
        cameraDevice?.close()
        imageReader?.close()
        captureSession = null
        cameraDevice = null
        imageReader = null
    }

    // -------------------------------------------------------------------------
    // Signals
    // -------------------------------------------------------------------------

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("camera_opened"),
        SignalInfo("camera_closed"),
        SignalInfo("camera_error", Int::class.java),
        SignalInfo("frame_available", ByteArray::class.java),
    )

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    private fun createSession() {
        val camera = cameraDevice ?: return
        val reader = imageReader ?: return

        camera.createCaptureSession(
            listOf(reader.surface),
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    captureSession = session
                    emitSignal("camera_opened")
                }
                override fun onConfigureFailed(session: CameraCaptureSession) {
                    emitSignal("camera_error", -3)
                }
            },
            handler
        )
    }

    // Convert YUV_420_888 → NV21 → JPEG
    private fun imageToJpeg(image: Image): ByteArray {
        val w = image.width
        val h = image.height
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        val nv21 = ByteArray(w * h * 3 / 2)

        // Y plane — copy row by row to handle non-packed strides
        val yRowStride = yPlane.rowStride
        val yBuffer = yPlane.buffer
        for (row in 0 until h) {
            yBuffer.position(row * yRowStride)
            yBuffer.get(nv21, row * w, w)
        }

        // Chroma — interleave V then U (NV21 order)
        val uvRowStride = vPlane.rowStride
        val uvPixelStride = vPlane.pixelStride
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer
        var pos = w * h
        for (row in 0 until h / 2) {
            for (col in 0 until w / 2) {
                val idx = row * uvRowStride + col * uvPixelStride
                nv21[pos++] = vBuffer.get(idx)
                nv21[pos++] = uBuffer.get(idx)
            }
        }

        val yuvImage = YuvImage(nv21, ImageFormat.NV21, w, h, null)
        val out = ByteArrayOutputStream()
        yuvImage.compressToJpeg(Rect(0, 0, w, h), 90, out)
        return out.toByteArray()
    }
}
