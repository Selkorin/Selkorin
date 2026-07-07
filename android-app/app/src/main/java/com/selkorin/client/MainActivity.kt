package com.selkorin.client

import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Bundle
import android.text.InputType
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.selkorin.client.databinding.ActivityMainBinding
import com.selkorin.client.databinding.DialogAddKeyBinding
import com.selkorin.client.databinding.DialogChangePasswordBinding
import com.selkorin.client.databinding.DialogKeyDetailBinding
import com.selkorin.client.databinding.DialogSettingsBinding
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {

    private lateinit var b: ActivityMainBinding
    private lateinit var vault: Vault
    private lateinit var vpn: VpnManager
    private lateinit var bio: BiometricHelper
    private lateinit var adapter: KeyAdapter

    private var setupMode = false
    private var activeKeyId: String? = null
    private var pendingConnect: Vault.KeyMeta? = null
    private var busy = false

    private val vpnPermissionLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { res ->
        val key = pendingConnect
        pendingConnect = null
        if (res.resultCode == RESULT_OK && key != null) doConnect(key)
        else if (key != null) toast(getString(R.string.vpn_permission_needed))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        b = ActivityMainBinding.inflate(layoutInflater)
        setContentView(b.root)

        vault = Vault(this)
        vpn = VpnManager(this)
        bio = BiometricHelper(this)

        adapter = KeyAdapter(emptyList(), null, ::onKeyClick, ::onKeyMenu)
        b.keyList.layoutManager = LinearLayoutManager(this)
        b.keyList.adapter = adapter

        b.lockBtn.setOnClickListener { submitLock() }
        b.bioBtn.setOnClickListener { attemptBiometricUnlock() }
        b.settingsBtn.setOnClickListener { openSettings() }
        b.powerBtn.setOnClickListener { onPower() }
        b.addKeyBtn.setOnClickListener { openAddKey() }

        if (!vault.isConfigured()) showLock(true) else showLock(false)
    }

    // ---------- экран блокировки ----------
    private fun showLock(setup: Boolean) {
        setupMode = setup
        b.lockView.visibility = android.view.View.VISIBLE
        b.mainView.visibility = android.view.View.GONE
        b.lockSub.setText(if (setup) R.string.lock_sub_setup else R.string.lock_sub_unlock)
        b.lockPass2.visibility = if (setup) android.view.View.VISIBLE else android.view.View.GONE
        b.lockBtn.setText(if (setup) R.string.btn_setup else R.string.btn_unlock)
        b.lockPass.setText("")
        b.lockPass2.setText("")
        b.lockErr.text = ""
        val canBio = !setup && vault.isBiometricEnabled() && bio.isSupported()
        b.bioBtn.visibility = if (canBio) android.view.View.VISIBLE else android.view.View.GONE
    }

    private fun submitLock() {
        val pass = b.lockPass.text.toString()
        if (setupMode) {
            if (pass.length < 4) { b.lockErr.setText(R.string.err_min_len); return }
            if (pass != b.lockPass2.text.toString()) { b.lockErr.setText(R.string.err_mismatch); return }
            vault.setupPassword(pass)
            showMain()
        } else {
            if (vault.unlock(pass)) showMain()
            else b.lockErr.setText(R.string.err_wrong)
        }
    }

    private fun attemptBiometricUnlock() {
        bio.unlock(vault) { ok, err ->
            runOnUiThread {
                if (ok) showMain() else if (err != null) b.lockErr.text = err
            }
        }
    }

    private fun showMain() {
        b.lockView.visibility = android.view.View.GONE
        b.mainView.visibility = android.view.View.VISIBLE
        refreshKeys()
        renderConn()
    }

    // ---------- ключи ----------
    private fun refreshKeys() {
        val keys = vault.listKeys()
        adapter.update(keys, if (vpn.isConnected()) activeKeyId else null)
        b.keyEmpty.visibility = if (keys.isEmpty()) android.view.View.VISIBLE else android.view.View.GONE
        b.keyList.visibility = if (keys.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE
    }

    private fun detectType(secret: String): String? {
        val s = secret.trim()
        return when {
            s.startsWith("vless://", ignoreCase = true) -> "vless"
            s.contains("[Interface]", ignoreCase = true) && s.contains("PrivateKey", ignoreCase = true) -> "wireguard"
            else -> null
        }
    }

    private fun openAddKey() {
        val db = DialogAddKeyBinding.inflate(layoutInflater)
        val dlg = AlertDialog.Builder(this, R.style.Theme_Selkorin_Dialog).setView(db.root).create()
        db.addKeyCancel.setOnClickListener { dlg.dismiss() }
        db.addKeySave.setOnClickListener {
            val secret = db.keySecretInput.text.toString().trim()
            val type = detectType(secret)
            if (type == null) { toast(getString(R.string.key_invalid)); return@setOnClickListener }
            val name = db.keyNameInput.text.toString().trim().ifBlank { if (type == "vless") "VLESS" else "WireGuard" }
            vault.addKey(name, type, secret)
            dlg.dismiss()
            refreshKeys()
            toast(getString(R.string.key_added))
            if (type == "vless") toast(getString(R.string.vless_not_supported))
        }
        dlg.show()
    }

    private fun onKeyMenu(item: Vault.KeyMeta) {
        val db = DialogKeyDetailBinding.inflate(layoutInflater)
        val secret = try { vault.getSecret(item.id) } catch (e: Exception) { "" }
        db.detailName.text = item.name
        db.detailType.text = if (item.type == "vless") "VLESS · Reality" else "WireGuard"
        db.detailSecret.text = secret
        val dlg = AlertDialog.Builder(this, R.style.Theme_Selkorin_Dialog).setView(db.root).create()
        db.detailClose.setOnClickListener { dlg.dismiss() }
        db.detailCopy.setOnClickListener {
            val cm = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
            cm.setPrimaryClip(android.content.ClipData.newPlainText("selkorin-key", secret))
            toast(getString(R.string.copied))
        }
        db.detailDelete.setOnClickListener {
            if (activeKeyId == item.id && vpn.isConnected()) { toast("Сначала отключитесь"); return@setOnClickListener }
            vault.removeKey(item.id)
            dlg.dismiss()
            refreshKeys()
            toast(getString(R.string.key_removed))
        }
        dlg.show()
    }

    private fun onKeyClick(item: Vault.KeyMeta) {
        if (vpn.isConnected() && activeKeyId == item.id) disconnect() else connect(item)
    }

    // ---------- подключение ----------
    private fun onPower() {
        if (busy) return
        if (vpn.isConnected()) { disconnect(); return }
        val keys = vault.listKeys()
        val target = keys.firstOrNull { it.id == activeKeyId } ?: keys.firstOrNull()
        if (target == null) { openAddKey(); return }
        connect(target)
    }

    private fun connect(meta: Vault.KeyMeta) {
        if (meta.type == "vless") { toast(getString(R.string.vless_not_supported)); return }
        val prepareIntent = vpn.prepareIntent(this)
        if (prepareIntent != null) { pendingConnect = meta; vpnPermissionLauncher.launch(prepareIntent); return }
        doConnect(meta)
    }

    private fun doConnect(meta: Vault.KeyMeta) {
        setBusy(true)
        lifecycleScope.launch {
            try {
                val secret = vault.getSecret(meta.id)
                vpn.connect(meta.name, secret)
                activeKeyId = meta.id
                toast(getString(R.string.connected_to, meta.name))
            } catch (e: Exception) {
                toast(e.message ?: getString(R.string.wg_not_installed))
            } finally {
                setBusy(false)
                refreshKeys()
                renderConn()
            }
        }
    }

    private fun disconnect() {
        setBusy(true)
        lifecycleScope.launch {
            try { vpn.disconnect(); activeKeyId = null; toast(getString(R.string.disconnected)) }
            catch (e: Exception) { toast(e.message ?: "Ошибка") }
            finally { setBusy(false); refreshKeys(); renderConn() }
        }
    }

    private fun setBusy(v: Boolean) { busy = v }

    private fun renderConn() {
        val on = vpn.isConnected()
        b.powerBtn.setBackgroundResource(if (on) R.drawable.bg_power_on else R.drawable.bg_power_off)
        b.powerIco.setTextColor(resources.getColor(if (on) R.color.ok else R.color.muted, theme))
        b.heroStatus.setText(if (on) R.string.status_on else R.string.status_off)
        b.heroStatus.setTextColor(resources.getColor(if (on) R.color.ok else R.color.text, theme))
        val cur = vault.listKeys().firstOrNull { it.id == activeKeyId }
        b.heroServer.text = when {
            on && cur != null -> cur.name
            vault.listKeys().isNotEmpty() -> getString(R.string.tap_to_connect)
            else -> getString(R.string.no_key_selected)
        }
    }

    // ---------- настройки ----------
    private fun openSettings() {
        val db = DialogSettingsBinding.inflate(layoutInflater)
        val dlg = AlertDialog.Builder(this, R.style.Theme_Selkorin_Dialog).setView(db.root).create()

        val bioSupported = bio.isSupported()
        db.bioSwitch.isEnabled = bioSupported
        db.bioSwitch.isChecked = vault.isBiometricEnabled()
        if (!bioSupported) db.bioSub.setText(R.string.settings_biometric_unsupported)
        db.bioSwitch.setOnCheckedChangeListener { _, checked ->
            if (checked) {
                promptPassword { pw ->
                    bio.enable(pw, vault) { ok, err ->
                        runOnUiThread {
                            if (!ok) { db.bioSwitch.isChecked = false; toast(err ?: "Не удалось включить") }
                            else toast("Биометрия включена")
                        }
                    }
                }
            } else {
                bio.disable(vault)
            }
        }

        db.disguiseSwitch.isChecked = vault.isDisguised()
        db.disguiseSwitch.setOnCheckedChangeListener { _, checked -> setDisguise(checked) }

        db.changePasswordBtn.setOnClickListener { dlg.dismiss(); openChangePassword() }
        db.lockNowBtn.setOnClickListener { vault.lock(); dlg.dismiss(); showLock(false) }
        db.settingsClose.setOnClickListener { dlg.dismiss() }
        dlg.show()
    }

    private fun promptPassword(onOk: (String) -> Unit) {
        val input = android.widget.EditText(this).apply { inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD }
        AlertDialog.Builder(this, R.style.Theme_Selkorin_Dialog)
            .setTitle("Подтвердите пароль")
            .setView(input)
            .setPositiveButton("OK") { _, _ -> onOk(input.text.toString()) }
            .setNegativeButton(R.string.cancel, null)
            .show()
    }

    private fun setDisguise(enabled: Boolean) {
        val pm = packageManager
        val real = ComponentName(this, "com.selkorin.client.LauncherReal")
        val disguised = ComponentName(this, "com.selkorin.client.LauncherDisguised")
        if (enabled) {
            pm.setComponentEnabledSetting(real, PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
            pm.setComponentEnabledSetting(disguised, PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
            toast("Значок изменён на «Заметки»")
        } else {
            pm.setComponentEnabledSetting(disguised, PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
            pm.setComponentEnabledSetting(real, PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
            toast("Значок восстановлен")
        }
        vault.setDisguised(enabled)
    }

    private fun openChangePassword() {
        val db = DialogChangePasswordBinding.inflate(layoutInflater)
        val dlg = AlertDialog.Builder(this, R.style.Theme_Selkorin_Dialog).setView(db.root).create()
        db.changePassCancel.setOnClickListener { dlg.dismiss() }
        db.changePassSave.setOnClickListener {
            val n1 = db.newPassInput.text.toString()
            val n2 = db.repeatPassInput.text.toString()
            if (n1.length < 4) { toast(getString(R.string.err_min_len)); return@setOnClickListener }
            if (n1 != n2) { toast(getString(R.string.err_mismatch)); return@setOnClickListener }
            try {
                vault.changePassword(db.oldPassInput.text.toString(), n1)
                dlg.dismiss()
                toast("Пароль изменён")
            } catch (e: Exception) { toast(e.message ?: getString(R.string.err_wrong)) }
        }
        dlg.show()
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
}
