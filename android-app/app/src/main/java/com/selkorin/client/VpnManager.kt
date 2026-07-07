package com.selkorin.client

import android.content.Context
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream

/**
 * Обёртка над официальной библиотекой WireGuard (com.wireguard.android:tunnel).
 * GoBackend сам поднимает com.wireguard.android.backend.GoBackend$VpnService
 * (объявлен в манифесте) и запускает встроенный туннель — никакого
 * стороннего бинарника заливать не нужно.
 */
class VpnManager(context: Context) {

    private val backend = GoBackend(context.applicationContext)
    private var activeTunnel: SimpleTunnel? = null

    class SimpleTunnel(private val tunnelName: String) : Tunnel {
        override fun getName(): String = tunnelName
        override fun onStateChange(newState: Tunnel.State) {}
    }

    /** Возвращает Intent для запроса разрешения на VPN, либо null если уже разрешено. */
    fun prepareIntent(context: Context) = android.net.VpnService.prepare(context)

    suspend fun connect(name: String, confText: String): Boolean = withContext(Dispatchers.IO) {
        val safeName = name.replace(Regex("[^a-zA-Z0-9_-]"), "").ifBlank { "selkorin" }
        val config = Config.parse(ByteArrayInputStream(confText.toByteArray(Charsets.UTF_8)))
        val tunnel = SimpleTunnel(safeName)
        backend.setState(tunnel, Tunnel.State.UP, config)
        activeTunnel = tunnel
        true
    }

    suspend fun disconnect(): Boolean = withContext(Dispatchers.IO) {
        val tunnel = activeTunnel ?: return@withContext true
        backend.setState(tunnel, Tunnel.State.DOWN, null)
        activeTunnel = null
        true
    }

    fun isConnected(): Boolean = activeTunnel != null
}
