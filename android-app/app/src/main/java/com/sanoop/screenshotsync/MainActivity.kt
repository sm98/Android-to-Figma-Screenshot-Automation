package com.sanoop.screenshotsync

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.sanoop.screenshotsync.pairing.PairedMacStore
import com.sanoop.screenshotsync.pairing.PairingClient
import com.sanoop.screenshotsync.pairing.PairingResult
import com.sanoop.screenshotsync.pairing.QRPayload
import com.sanoop.screenshotsync.pairing.QRScannerScreen
import com.sanoop.screenshotsync.service.ScreenshotWatcherService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private sealed interface AppScreen {
    data object Home : AppScreen
    data object Scanning : AppScreen
    data object Pairing : AppScreen
}

class MainActivity : ComponentActivity() {

    private lateinit var pairedMacStore: PairedMacStore
    private var pendingCameraGrantCallback: ((Boolean) -> Unit)? = null

    private val cameraPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> pendingCameraGrantCallback?.invoke(granted) }

    private val watcherPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { /* if denied, the toggle can simply be tried again later */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pairedMacStore = PairedMacStore(applicationContext)

        setContent {
            MaterialTheme {
                var screen by remember { mutableStateOf<AppScreen>(AppScreen.Home) }
                var pairedMacName by remember { mutableStateOf(pairedMacStore.load()?.macDeviceName) }
                var statusMessage by remember { mutableStateOf<String?>(null) }
                val scope = rememberCoroutineScope()

                when (screen) {
                    AppScreen.Home -> HomeScreen(
                        pairedMacName = pairedMacName,
                        statusMessage = statusMessage,
                        onPairClicked = {
                            requestCameraThenRun { screen = AppScreen.Scanning }
                        },
                        onStartWatching = {
                            requestWatcherPermissions()
                            startWatcherService()
                        },
                        onStopWatching = { stopWatcherService() }
                    )

                    AppScreen.Scanning -> QRScannerScreen(onScanned = { raw ->
                        val payload = QRPayload.parse(raw)
                        if (payload == null) {
                            statusMessage = "Unrecognized QR code"
                            screen = AppScreen.Home
                        } else {
                            screen = AppScreen.Pairing
                            scope.launch {
                                val result = withContext(Dispatchers.IO) {
                                    PairingClient.pair(payload, androidDeviceName())
                                }
                                when (result) {
                                    is PairingResult.Success -> {
                                        pairedMacStore.save(result.paired)
                                        pairedMacName = result.paired.macDeviceName
                                        statusMessage = "Paired with ${result.paired.macDeviceName}"
                                    }
                                    is PairingResult.Failure -> {
                                        statusMessage = "Pairing failed: ${result.message}"
                                    }
                                }
                                screen = AppScreen.Home
                            }
                        }
                    })

                    AppScreen.Pairing -> PairingInProgressScreen()
                }
            }
        }
    }

    private fun requestCameraThenRun(onGranted: () -> Unit) {
        val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) {
            onGranted()
        } else {
            pendingCameraGrantCallback = { wasGranted -> if (wasGranted) onGranted() }
            cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    private fun requestWatcherPermissions() {
        val permissions = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
            permissions.add(Manifest.permission.READ_MEDIA_IMAGES)
        } else {
            permissions.add(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        val needed = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (needed.isNotEmpty()) {
            watcherPermissionLauncher.launch(needed.toTypedArray())
        }
    }

    private fun startWatcherService() {
        ContextCompat.startForegroundService(this, Intent(this, ScreenshotWatcherService::class.java))
    }

    private fun stopWatcherService() {
        stopService(Intent(this, ScreenshotWatcherService::class.java))
    }

    private fun androidDeviceName(): String = Build.MODEL ?: "Android device"
}

@Composable
private fun HomeScreen(
    pairedMacName: String?,
    statusMessage: String?,
    onPairClicked: () -> Unit,
    onStartWatching: () -> Unit,
    onStopWatching: () -> Unit
) {
    var isWatching by remember { mutableStateOf(false) }

    Surface(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text("Screenshot Sync", style = MaterialTheme.typography.headlineMedium)
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                pairedMacName?.let { "Paired with $it" } ?: "Not paired with a Mac yet.",
                style = MaterialTheme.typography.bodyMedium
            )
            statusMessage?.let {
                Spacer(modifier = Modifier.height(8.dp))
                Text(it, style = MaterialTheme.typography.bodySmall)
            }
            Spacer(modifier = Modifier.height(24.dp))
            Button(onClick = onPairClicked) {
                Text(if (pairedMacName == null) "Pair with Mac" else "Re-pair with Mac")
            }
            Spacer(modifier = Modifier.height(12.dp))
            Button(onClick = {
                if (isWatching) onStopWatching() else onStartWatching()
                isWatching = !isWatching
            }) {
                Text(if (isWatching) "Stop Watching" else "Start Watching")
            }
        }
    }
}

@Composable
private fun PairingInProgressScreen() {
    Surface(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            CircularProgressIndicator()
            Spacer(modifier = Modifier.height(12.dp))
            Text("Pairing…")
        }
    }
}
