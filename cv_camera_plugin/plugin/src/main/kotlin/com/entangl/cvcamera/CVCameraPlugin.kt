package com.entangl.cvcamera

import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.hardware.camera2.*
import android.media.Image
import android.media.ImageReader
import android.media.MediaRecorder
import android.os.Build
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

    private var mediaRecorder: MediaRecorder? = null
    @Volatile private var isRecording = false
    @Volatile private var pendingStop = false
    private var recordingPath: String? = null

    // Action queued while waiting for the camera device to open.
    private var pendingAction: (() -> Unit)? = null

    // Incremented each time createSession is called; onConfigured checks its captured
    // value against the current one and discards stale callbacks.
    private var sessionGeneration = 0

    // -1 = auto, otherwise manual values set via setExposure() / setNoiseReduction()
    private var exposureTimeNs: Long = -1L
    private var sensitivity: Int = -1
    private var noiseReductionOff: Boolean = false

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    @UsedByGodot
    fun setExposure(exposureMs: Double, iso: Int) {
        exposureTimeNs = if (exposureMs < 0) -1L else (exposureMs * 1_000_000.0).toLong()
        sensitivity = iso
    }

    @UsedByGodot
    fun setNoiseReduction(enabled: Boolean) {
        noiseReductionOff = !enabled
    }

    // Prepares the ImageReader but does NOT open the camera device - no privacy indicator.
    // The device is opened lazily on the first captureFrame() or startRecording() call.
    @UsedByGodot
    fun openCamera(width: Int, height: Int) {
        imageReader = ImageReader.newInstance(width, height, ImageFormat.YUV_420_888, 2)
        emitSignal("camera_opened")
    }

    // Opens a photo session, captures one frame, closes the session and device.
    @UsedByGodot
    fun captureFrame() {
        if (isRecording) { emitSignal("camera_error", -2); return }
        withCameraDevice { doCaptureFrame() }
    }

    @UsedByGodot
    fun startRecording(filePath: String, width: Int, height: Int) {
        if (isRecording) return
        pendingStop = false
        recordingPath = filePath

        val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(godot.getActivity()!!)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }

        recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
        recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
        recorder.setVideoSize(width, height)
        recorder.setVideoFrameRate(30)
        recorder.setVideoEncodingBitRate(8_000_000)
        recorder.setOutputFile(filePath)
        recorder.prepare()

        mediaRecorder = recorder

        captureSession?.close()
        captureSession = null
        withCameraDevice { createRecordingSession() }
    }

    @UsedByGodot
    fun stopRecording() {
        if (!isRecording) {
            pendingStop = true
            return
        }
        handler.post { doStopRecording() }
    }

    @UsedByGodot
    fun closeCamera() {
        pendingAction = null
        if (isRecording) {
            try { mediaRecorder?.stop() } catch (e: Exception) {}
            mediaRecorder?.reset()
            mediaRecorder?.release()
            mediaRecorder = null
            isRecording = false
        }
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
        SignalInfo("recording_started"),
        SignalInfo("recording_stopped", String::class.java),
    )

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    // Runs action immediately if the device is already open, otherwise opens it first.
    private fun withCameraDevice(action: () -> Unit) {
        if (cameraDevice != null) {
            action()
            return
        }
        pendingAction = action
        val manager = godot.getActivity()!!
            .getSystemService(android.content.Context.CAMERA_SERVICE) as CameraManager
        try {
            manager.openCamera("0", object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    pendingAction?.invoke()
                    pendingAction = null
                }
                override fun onDisconnected(camera: CameraDevice) {
                    camera.close()
                    cameraDevice = null
                    pendingAction = null
                    emitSignal("camera_closed")
                }
                override fun onError(camera: CameraDevice, error: Int) {
                    camera.close()
                    cameraDevice = null
                    pendingAction = null
                    emitSignal("camera_error", error)
                }
            }, handler)
        } catch (e: SecurityException) {
            pendingAction = null
            emitSignal("camera_error", -1)
        }
    }

    private fun doCaptureFrame() {
        val camera = cameraDevice ?: return
        val reader = imageReader ?: return
        val gen = ++sessionGeneration

        reader.setOnImageAvailableListener({ r ->
            r.setOnImageAvailableListener(null, null)
            val image = r.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                emitSignal("frame_available", imageToJpeg(image))
            } finally {
                image.close()
                captureSession?.close()
                captureSession = null
                cameraDevice?.close()
                cameraDevice = null
            }
        }, handler)

        camera.createCaptureSession(
            listOf(reader.surface),
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    if (gen != sessionGeneration) { session.close(); return }
                    captureSession = session
                    val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
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
                    }.build()
                    session.capture(request, null, handler)
                }
                override fun onConfigureFailed(session: CameraCaptureSession) {
                    if (gen != sessionGeneration) return
                    cameraDevice?.close()
                    cameraDevice = null
                    emitSignal("camera_error", -3)
                }
            },
            handler
        )
    }

    private fun createRecordingSession() {
        val gen = ++sessionGeneration
        val camera = cameraDevice ?: return
        val recorder = mediaRecorder ?: return

        camera.createCaptureSession(
            listOf(recorder.surface),
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    if (gen != sessionGeneration) { session.close(); return }
                    captureSession = session

                    if (pendingStop) {
                        pendingStop = false
                        recorder.reset()
                        recorder.release()
                        mediaRecorder = null
                        session.close()
                        captureSession = null
                        cameraDevice?.close()
                        cameraDevice = null
                        emitSignal("recording_stopped", "")
                        return
                    }

                    // Start encoder before the repeating request - frames sent to the
                    // MediaRecorder surface before start() are dropped, causing green frames.
                    recorder.start()
                    isRecording = true
                    emitSignal("recording_started")

                    val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                        addTarget(recorder.surface)
                        if (noiseReductionOff) {
                            set(CaptureRequest.NOISE_REDUCTION_MODE, CaptureRequest.NOISE_REDUCTION_MODE_OFF)
                            set(CaptureRequest.EDGE_MODE, CaptureRequest.EDGE_MODE_OFF)
                        }
                        if (exposureTimeNs > 0 && sensitivity > 0) {
                            set(CaptureRequest.CONTROL_AE_MODE, CameraMetadata.CONTROL_AE_MODE_OFF)
                            set(CaptureRequest.SENSOR_EXPOSURE_TIME, exposureTimeNs)
                            set(CaptureRequest.SENSOR_SENSITIVITY, sensitivity)
                        }
                    }.build()
                    session.setRepeatingRequest(request, null, handler)
                }
                override fun onConfigureFailed(session: CameraCaptureSession) {
                    if (gen != sessionGeneration) return
                    cameraDevice?.close()
                    cameraDevice = null
                    emitSignal("camera_error", -3)
                }
            },
            handler
        )
    }

    private fun doStopRecording() {
        if (!isRecording) return
        isRecording = false
        pendingStop = false
        val path = recordingPath ?: ""

        try {
            captureSession?.stopRepeating()
            mediaRecorder?.stop()
        } catch (e: Exception) {
            emitSignal("camera_error", -4)
        }

        mediaRecorder?.reset()
        mediaRecorder?.release()
        mediaRecorder = null
        captureSession?.close()
        captureSession = null
        cameraDevice?.close()
        cameraDevice = null

        emitSignal("recording_stopped", path)
    }

    // Convert YUV_420_888 → NV21 → JPEG
    private fun imageToJpeg(image: Image): ByteArray {
        val w = image.width
        val h = image.height
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        val nv21 = ByteArray(w * h * 3 / 2)

        val yRowStride = yPlane.rowStride
        val yBuffer = yPlane.buffer
        for (row in 0 until h) {
            yBuffer.position(row * yRowStride)
            yBuffer.get(nv21, row * w, w)
        }

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
